/**
 * Novi edge — the custodian of the AI provider key.
 *
 * The Novi API used to hold the upstream key in its own environment. That is
 * already better than shipping it in the app, but it means the key's blast
 * radius is the whole API server: anything that can read that process's
 * environment can spend the account. This Worker narrows that to one place.
 *
 * After deploying, the API's `AI_BASE_URL` points here and its `AI_API_KEY`
 * becomes a SHARED SECRET, not the provider key. The Worker checks that secret,
 * swaps in the real one, and forwards. The provider key then exists only in
 * Cloudflare's secret store, which does not read back.
 *
 * It serves both wire protocols on the paths Novi's gateway already builds —
 * `POST /v1/messages` (Anthropic shape, `x-api-key`) and
 * `POST /v1/chat/completions` (OpenAI shape, bearer token) — and speaks the
 * provider's own error dialect, so the backend needed no code change at all.
 * Which one is in use is the API's `AI_PROTOCOL`; the Worker does not care,
 * it just has to custody the key on whichever path the request arrives on.
 *
 * What this genuinely protects, stated plainly:
 *   - The provider key is off the origin server entirely.
 *   - Spend is capped at the edge, before a request costs anything upstream.
 *   - Burst abuse is refused before it reaches the provider.
 * What it does NOT do: it is not a substitute for the API's own auth. Anyone
 * holding the shared secret can spend the budget, so treat it like a key.
 */

/** The provider's error shape, so the Novi backend's existing mapping works. */
function providerError(status: number, type: string, message: string): Response {
  return withSecurityHeaders(
    Response.json({ type: "error", error: { type, message } }, { status }),
  );
}

/** Structured, one line, never containing a prompt or a key. */
function log(event: string, fields: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ event, ...fields }));
}

/**
 * Constant-time secret comparison.
 *
 * `timingSafeEqual` requires equal-length buffers, and comparing raw secrets
 * of different lengths would throw — so both sides are hashed first. That also
 * means a length difference does not leak through the exception path.
 */
async function secretMatches(presented: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

const AT_REST = "nv1.";

function withSecurityHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("x-content-type-options", "nosniff");
  headers.set("x-frame-options", "DENY");
  headers.set("referrer-policy", "no-referrer");
  headers.set("permissions-policy", "camera=(), microphone=(), geolocation=()");
  return new Response(response.body, { status: response.status, headers });
}

async function cacheKeyMaterial(secret: string): Promise<CryptoKey> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`novi-at-rest-v1:${secret}`),
  );
  return crypto.subtle.importKey("raw", hash, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function bytesToB64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function b64urlToBytes(value: string): Uint8Array {
  const padded = value.replaceAll("-", "+").replaceAll("_", "/");
  const pad = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  const bin = atob(padded + pad);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function sealCache(plain: string, secret: string): Promise<string> {
  if (!plain || !secret) return plain;
  try {
    const key = await cacheKeyMaterial(secret);
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const sealed = new Uint8Array(
      await crypto.subtle.encrypt(
        { name: "AES-GCM", iv: nonce, additionalData: new TextEncoder().encode("novi-v1") },
        key,
        new TextEncoder().encode(plain),
      ),
    );
    const packed = new Uint8Array(nonce.length + sealed.length);
    packed.set(nonce);
    packed.set(sealed, nonce.length);
    return AT_REST + bytesToB64url(packed);
  } catch {
    return plain;
  }
}

async function openCache(value: string, secret: string): Promise<string | null> {
  if (value === null || value === undefined) return null;
  if (!value.startsWith(AT_REST)) return value;
  try {
    const key = await cacheKeyMaterial(secret);
    const packed = b64urlToBytes(value.slice(AT_REST.length));
    const opened = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv: packed.slice(0, 12),
        additionalData: new TextEncoder().encode("novi-v1"),
      },
      key,
      packed.slice(12),
    );
    return new TextDecoder().decode(opened);
  } catch {
    return null;
  }
}

/** SHA-256 of the exact request body, hex — the cache key. */
async function bodyHash(body: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(body));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function utcDay(now: Date): string {
  return now.toISOString().slice(0, 10);
}

/**
 * The day's request budget.
 *
 * KV is eventually consistent and this is a read-then-write, so under
 * concurrency it can let a few extra requests through. That is a deliberate
 * trade: this is a guard rail against a runaway loop or a leaked secret, not
 * an accounting ledger. A Durable Object would count exactly and would add a
 * stateful hop to every request for a number nobody bills against.
 */
async function withinBudget(env: Env, now: Date): Promise<{ ok: boolean; used: number }> {
  const cap = Number(env.DAILY_REQUEST_CAP);
  if (!Number.isFinite(cap) || cap <= 0) return { ok: true, used: 0 };

  const key = `budget:${utcDay(now)}`;
  const used = Number(await env.EDGE_KV.get(key)) || 0;
  return { ok: used < cap, used };
}

async function recordSpend(env: Env, now: Date, used: number): Promise<void> {
  const key = `budget:${utcDay(now)}`;
  // Two days, so yesterday's counter is still readable for a moment after
  // midnight UTC and does not vanish mid-request.
  await env.EDGE_KV.put(key, String(used + 1), { expirationTtl: 60 * 60 * 48 });
}

/** The shared secret, from whichever header this protocol puts it in. */
function presentedSecret(request: Request): string {
  const key = request.headers.get("x-api-key");
  if (key) return key;
  const auth = request.headers.get("authorization") ?? "";
  return auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
}

type Protocol = "anthropic" | "openai";

async function handleProxy(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  protocol: Protocol,
): Promise<Response> {
  // ── Who is calling ───────────────────────────────────────────────────────
  const presented = presentedSecret(request);
  if (!presented || !(await secretMatches(presented, env.EDGE_SHARED_SECRET))) {
    log("edge_auth_rejected", { protocol });
    return providerError(401, "authentication_error", "Edge proxy rejected the caller");
  }

  // ── Size, before reading ─────────────────────────────────────────────────
  const maxBytes = Number(env.MAX_REQUEST_BYTES) || 262_144;
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > maxBytes) {
    return providerError(413, "invalid_request_error", "Request body too large");
  }

  // An explanation prompt is a few KB, so buffering is correct here — it is
  // what makes caching and hashing possible. The cap above is what keeps it
  // bounded; `await request.text()` on an unbounded body would not be safe.
  const body = await request.text();
  if (body.length > maxBytes) {
    return providerError(413, "invalid_request_error", "Request body too large");
  }

  let parsed: { model?: string; stream?: boolean; temperature?: number };
  try {
    parsed = JSON.parse(body) as typeof parsed;
  } catch {
    return providerError(400, "invalid_request_error", "Body is not valid JSON");
  }

  // ── Burst ────────────────────────────────────────────────────────────────
  // The generated type says this binding is always present. In practice it is
  // not emulated by every local runtime, and an absent binding threw on every
  // request — a defence-in-depth layer taking down the thing it defends. It
  // degrades loudly instead: the request proceeds, and the gap is logged so it
  // is visible rather than silent.
  const limiter = env.BURST_LIMIT as RateLimit | undefined;
  if (limiter) {
    const burst = await limiter.limit({ key: presented.slice(0, 32) });
    if (!burst.success) {
      log("edge_burst_limited");
      return providerError(429, "rate_limit_error", "Too many requests to the edge proxy");
    }
  } else {
    log("edge_burst_limiter_absent");
  }

  // ── Cache ────────────────────────────────────────────────────────────────
  // Only deterministic requests are cached. A high temperature means the
  // caller wants variety, and handing back a stored answer would quietly
  // remove it. Streaming is never cached: the body is consumed as it flows.
  const ttl = Number(env.CACHE_TTL_SECONDS) || 0;
  const cacheable = ttl > 0 && parsed.stream !== true && (parsed.temperature ?? 0) <= 0.3;
  // The protocol is part of the key: the same prompt sent both ways produces
  // two differently-shaped responses, and one entry serving both would hand a
  // caller a body it cannot parse.
  const cacheKey = cacheable ? `ai:${protocol}:${await bodyHash(body)}` : null;

  if (cacheKey) {
    const hit = await env.EDGE_KV.get(cacheKey);
    if (hit !== null) {
      const body = await openCache(hit, env.EDGE_SHARED_SECRET);
      if (body !== null) {
        log("edge_cache_hit", { model: parsed.model });
        return withSecurityHeaders(
          new Response(body, {
            status: 200,
            headers: { "content-type": "application/json", "x-novi-edge": "hit" },
          }),
        );
      }
    }
  }

  // ── Budget ───────────────────────────────────────────────────────────────
  const now = new Date();
  const budget = await withinBudget(env, now);
  if (!budget.ok) {
    log("edge_budget_exhausted", { used: budget.used });
    // Reported as a rate limit on purpose: the Novi backend already maps that
    // to a temporary "tutor unavailable", which is exactly what this is.
    return providerError(429, "rate_limit_error", "Daily edge budget reached");
  }

  // ── Forward ──────────────────────────────────────────────────────────────
  const base = env.PROVIDER_BASE_URL.replace(/\/$/, "");
  const upstream =
    protocol === "anthropic" ? `${base}/messages` : `${base}/chat/completions`;

  // The swap. This is the whole point of the Worker: the caller's shared
  // secret never leaves this function, and the real key never leaves Cloudflare.
  const headers: Record<string, string> =
    protocol === "anthropic"
      ? {
          "x-api-key": env.PROVIDER_API_KEY,
          "anthropic-version": request.headers.get("anthropic-version") ?? "2023-06-01",
          "content-type": "application/json",
        }
      : {
          authorization: `Bearer ${env.PROVIDER_API_KEY}`,
          "content-type": "application/json",
        };

  const started = Date.now();

  let response: Response;
  try {
    response = await fetch(upstream, { method: "POST", headers, body });
  } catch (error) {
    log("edge_upstream_unreachable", { error: String(error) });
    return providerError(502, "api_error", "Could not reach the AI provider");
  }

  ctx.waitUntil(recordSpend(env, now, budget.used));
  log("edge_forwarded", {
    protocol,
    model: parsed.model,
    status: response.status,
    latency_ms: Date.now() - started,
  });

  // A streamed reply is passed straight through without being buffered.
  if (parsed.stream === true) {
    return withSecurityHeaders(
      new Response(response.body, {
        status: response.status,
        headers: { "content-type": response.headers.get("content-type") ?? "text/event-stream" },
      }),
    );
  }

  const text = await response.text();

  // Only successful answers are cached. Caching a "rate limit exceeded" would
  // pin the outage in place for the whole TTL.
  if (cacheKey && response.ok && !text.includes('"type":"error"')) {
    ctx.waitUntil(
      sealCache(text, env.EDGE_SHARED_SECRET).then((sealed) =>
        env.EDGE_KV.put(cacheKey, sealed, { expirationTtl: ttl }),
      ),
    );
  }

  return withSecurityHeaders(
    new Response(text, {
      status: response.status,
      headers: { "content-type": "application/json", "x-novi-edge": "miss" },
    }),
  );
}

function handleHealth(): Response {
  return withSecurityHeaders(Response.json({ status: "ok", service: "novi-edge" }));
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    try {
      if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/")) {
        return handleHealth();
      }
      if (request.method === "POST" && url.pathname === "/v1/messages") {
        return await handleProxy(request, env, ctx, "anthropic");
      }
      if (request.method === "POST" && url.pathname === "/v1/chat/completions") {
        return await handleProxy(request, env, ctx, "openai");
      }
      return providerError(404, "not_found_error", "No such route on the edge proxy");
    } catch (error) {
      // Explicit, rather than passThroughOnException: an unhandled throw
      // should be a logged error and a structured response, not a silent
      // fall-through to the origin.
      console.error(JSON.stringify({ event: "edge_unhandled", error: String(error) }));
      return providerError(500, "api_error", "Edge proxy failed");
    }
  },
} satisfies ExportedHandler<Env>;
