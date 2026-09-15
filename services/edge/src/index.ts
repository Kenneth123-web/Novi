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
 * It serves `POST /v1/messages` because that is exactly the path Novi's
 * gateway already builds (`{AI_BASE_URL}/messages`), and it speaks the
 * provider's own error dialect — so the backend needed no code change at all.
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
  return Response.json({ type: "error", error: { type, message } }, { status });
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

async function handleMessages(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  // ── Who is calling ───────────────────────────────────────────────────────
  const presented = request.headers.get("x-api-key") ?? "";
  if (!presented || !(await secretMatches(presented, env.EDGE_SHARED_SECRET))) {
    log("edge_auth_rejected");
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
  const cacheKey = cacheable ? `ai:${await bodyHash(body)}` : null;

  if (cacheKey) {
    const hit = await env.EDGE_KV.get(cacheKey);
    if (hit !== null) {
      log("edge_cache_hit", { model: parsed.model });
      return new Response(hit, {
        status: 200,
        headers: { "content-type": "application/json", "x-novi-edge": "hit" },
      });
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
  const upstream = `${env.PROVIDER_BASE_URL.replace(/\/$/, "")}/messages`;
  const started = Date.now();

  let response: Response;
  try {
    response = await fetch(upstream, {
      method: "POST",
      headers: {
        // The swap. This is the whole point of the Worker.
        "x-api-key": env.PROVIDER_API_KEY,
        "anthropic-version": request.headers.get("anthropic-version") ?? "2023-06-01",
        "content-type": "application/json",
      },
      body,
    });
  } catch (error) {
    log("edge_upstream_unreachable", { error: String(error) });
    return providerError(502, "api_error", "Could not reach the AI provider");
  }

  ctx.waitUntil(recordSpend(env, now, budget.used));
  log("edge_forwarded", {
    model: parsed.model,
    status: response.status,
    latency_ms: Date.now() - started,
  });

  // A streamed reply is passed straight through without being buffered.
  if (parsed.stream === true) {
    return new Response(response.body, {
      status: response.status,
      headers: { "content-type": response.headers.get("content-type") ?? "text/event-stream" },
    });
  }

  const text = await response.text();

  // Only successful answers are cached. Caching a "rate limit exceeded" would
  // pin the outage in place for the whole TTL.
  if (cacheKey && response.ok && !text.includes('"type":"error"')) {
    ctx.waitUntil(env.EDGE_KV.put(cacheKey, text, { expirationTtl: ttl }));
  }

  return new Response(text, {
    status: response.status,
    headers: { "content-type": "application/json", "x-novi-edge": "miss" },
  });
}

function handleHealth(env: Env): Response {
  // Reports whether each secret is PRESENT. Never any part of its value.
  return Response.json({
    status: "ok",
    service: "novi-edge",
    provider_key: env.PROVIDER_API_KEY ? "configured" : "missing",
    shared_secret: env.EDGE_SHARED_SECRET ? "configured" : "missing",
    cache_ttl_seconds: Number(env.CACHE_TTL_SECONDS) || 0,
    daily_request_cap: Number(env.DAILY_REQUEST_CAP) || 0,
  });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    try {
      if (request.method === "GET" && (url.pathname === "/health" || url.pathname === "/")) {
        return handleHealth(env);
      }
      if (request.method === "POST" && url.pathname === "/v1/messages") {
        return await handleMessages(request, env, ctx);
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
