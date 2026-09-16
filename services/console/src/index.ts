/**
 * Novi console — accounts, login events, and API usage, plus the admin site.
 *
 * The iOS app still signs in against the FastAPI origin (passwords and JWTs
 * live there, next to the learning data). This Worker is the ledger the
 * origin writes to, and the place an operator looks at who is on the product
 * and what they are spending.
 *
 *   iOS ──▶ Novi API ──▶ novi-console (D1)
 *                │              ▲
 *                └──────────────┘  ingest / status
 *
 * The HTML in ./public is the admin site. /api/* and /health run in this
 * script first; everything else is a static asset.
 */

function json(data: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

function err(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

function log(event: string, fields: Record<string, unknown> = {}): void {
  console.log(JSON.stringify({ event, ...fields }));
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function secretMatches(presented: string, expected: string): Promise<boolean> {
  const encoder = new TextEncoder();
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  return crypto.subtle.timingSafeEqual(a, b);
}

function nowIso(): string {
  return new Date().toISOString();
}

function cookieValue(request: Request, name: string): string {
  const header = request.headers.get("cookie") ?? "";
  for (const part of header.split(";")) {
    const [rawKey, ...rest] = part.trim().split("=");
    if (rawKey === name) return rest.join("=");
  }
  return "";
}

function sessionCookie(token: string, secure: boolean, maxAge = 60 * 60 * 12): string {
  const parts = [
    `novi_console=${token}`,
    "Path=/",
    "HttpOnly",
    "SameSite=Lax",
    `Max-Age=${maxAge}`,
  ];
  if (secure) parts.push("Secure");
  return parts.join("; ");
}

async function requireOrigin(request: Request, env: Env): Promise<Response | null> {
  const presented = request.headers.get("x-novi-origin-secret") ?? "";
  if (!presented || !(await secretMatches(presented, env.CONSOLE_ORIGIN_SECRET))) {
    log("console_origin_rejected");
    return err(401, "UNAUTHORIZED", "Origin secret rejected");
  }
  return null;
}

async function requireAdmin(request: Request, env: Env): Promise<Response | null> {
  const token = cookieValue(request, "novi_console");
  if (!token) return err(401, "UNAUTHORIZED", "Sign in to continue");
  const hash = await sha256Hex(token);
  const row = await env.DB.prepare(
    "SELECT 1 AS ok FROM admin_sessions WHERE token_hash = ? AND expires_at > ?",
  )
    .bind(hash, nowIso())
    .first<{ ok: number }>();
  if (!row) return err(401, "UNAUTHORIZED", "Sign in to continue");
  return null;
}

type AccountBody = {
  id?: string;
  email?: string;
  username?: string;
  display_name?: string;
  is_admin?: boolean;
  is_active?: boolean;
  event?: string;
  source?: string;
  user_agent?: string;
  created_at?: string | null;
};

async function ingestAccount(env: Env, body: AccountBody): Promise<Response> {
  if (!body.id || !body.email || !body.username) {
    return err(422, "VALIDATION_ERROR", "id, email and username are required");
  }
  const at = nowIso();
  const created = body.created_at || at;
  const event = body.event || "logged_in";
  const isLogin = event === "logged_in" || event === "dev_skipped";
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO users (
         id, email, username, display_name, is_active, is_admin, source,
         created_at, last_seen_at, last_login_at, login_count
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET
         email = excluded.email,
         username = excluded.username,
         display_name = excluded.display_name,
         is_admin = excluded.is_admin,
         last_seen_at = excluded.last_seen_at,
         last_login_at = COALESCE(excluded.last_login_at, users.last_login_at),
         login_count = users.login_count + excluded.login_count`,
    ).bind(
      body.id,
      String(body.email).toLowerCase(),
      body.username,
      body.display_name ?? "",
      body.is_active === false ? 0 : 1,
      body.is_admin ? 1 : 0,
      body.source || "register",
      created,
      at,
      isLogin ? at : null,
      isLogin ? 1 : 0,
    ),
    env.DB.prepare(
      `INSERT INTO login_events (user_id, event, source, user_agent, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).bind(body.id, event, body.source || "", (body.user_agent || "").slice(0, 255), at),
  ]);
  log("console_account_ingested", { user_id: body.id, kind: event });
  return new Response(null, { status: 204 });
}

type UsageBody = {
  user_id?: string | null;
  method?: string;
  path?: string;
  status?: number;
  latency_ms?: number;
  request_id?: string | null;
  kind?: string;
  model?: string | null;
  input_tokens?: number | null;
  output_tokens?: number | null;
};

async function ingestUsage(env: Env, body: UsageBody): Promise<Response> {
  if (!body.method || !body.path || typeof body.status !== "number") {
    return err(422, "VALIDATION_ERROR", "method, path and status are required");
  }
  await env.DB.prepare(
    `INSERT INTO api_usage (
       user_id, method, path, status, latency_ms, request_id, kind, model,
       input_tokens, output_tokens, created_at
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      body.user_id ?? null,
      body.method,
      String(body.path).slice(0, 200),
      body.status,
      Number(body.latency_ms) || 0,
      body.request_id ?? null,
      body.kind || "http",
      body.model ?? null,
      body.input_tokens ?? null,
      body.output_tokens ?? null,
      nowIso(),
    )
    .run();
  return new Response(null, { status: 204 });
}

async function userStatus(env: Env, id: string): Promise<Response> {
  const row = await env.DB.prepare("SELECT is_active FROM users WHERE id = ?")
    .bind(id)
    .first<{ is_active: number }>();
  if (!row) return json({ is_active: true, known: false });
  return json({ is_active: row.is_active === 1, known: true });
}

async function adminLogin(request: Request, env: Env): Promise<Response> {
  let body: { password?: string };
  try {
    body = (await request.json()) as { password?: string };
  } catch {
    return err(400, "BAD_REQUEST", "Body is not valid JSON");
  }
  const presented = body.password ?? "";
  if (!presented || !(await secretMatches(presented, env.ADMIN_PASSWORD))) {
    log("console_admin_login_rejected");
    return err(401, "UNAUTHORIZED", "Wrong password");
  }
  const token = crypto.randomUUID() + crypto.randomUUID();
  const hash = await sha256Hex(token);
  const created = nowIso();
  const expires = new Date(Date.now() + 12 * 60 * 60 * 1000).toISOString();
  await env.DB.prepare(
    "INSERT INTO admin_sessions (token_hash, created_at, expires_at) VALUES (?, ?, ?)",
  )
    .bind(hash, created, expires)
    .run();
  const secure = new URL(request.url).protocol === "https:";
  log("console_admin_login");
  return json({ ok: true }, 200, { "set-cookie": sessionCookie(token, secure) });
}

async function adminLogout(request: Request, env: Env): Promise<Response> {
  const token = cookieValue(request, "novi_console");
  if (token) {
    await env.DB.prepare("DELETE FROM admin_sessions WHERE token_hash = ?")
      .bind(await sha256Hex(token))
      .run();
  }
  const secure = new URL(request.url).protocol === "https:";
  return json({ ok: true }, 200, { "set-cookie": sessionCookie("", secure, 0) });
}

async function adminStats(env: Env): Promise<Response> {
  const dayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const weekAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const [users, active, logins, requests, tokens, top, series] = await Promise.all([
    env.DB.prepare("SELECT COUNT(*) AS n FROM users").first<{ n: number }>(),
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE is_active = 1").first<{ n: number }>(),
    env.DB.prepare(
      "SELECT COUNT(*) AS n FROM login_events WHERE created_at >= ? AND event IN ('logged_in', 'dev_skipped')",
    )
      .bind(dayAgo)
      .first<{ n: number }>(),
    env.DB.prepare("SELECT COUNT(*) AS n FROM api_usage WHERE created_at >= ?")
      .bind(dayAgo)
      .first<{ n: number }>(),
    env.DB.prepare(
      `SELECT COALESCE(SUM(input_tokens), 0) AS input,
              COALESCE(SUM(output_tokens), 0) AS output
       FROM api_usage WHERE kind = 'ai' AND created_at >= ?`,
    )
      .bind(dayAgo)
      .first<{ input: number; output: number }>(),
    env.DB.prepare(
      `SELECT path, COUNT(*) AS n FROM api_usage
       WHERE created_at >= ? GROUP BY path ORDER BY n DESC LIMIT 8`,
    )
      .bind(weekAgo)
      .all<{ path: string; n: number }>(),
    env.DB.prepare(
      `SELECT substr(created_at, 1, 10) AS day, COUNT(*) AS n
       FROM api_usage WHERE created_at >= ?
       GROUP BY day ORDER BY day`,
    )
      .bind(weekAgo)
      .all<{ day: string; n: number }>(),
  ]);
  return json({
    users: users?.n ?? 0,
    active_users: active?.n ?? 0,
    logins_24h: logins?.n ?? 0,
    requests_24h: requests?.n ?? 0,
    ai_input_tokens_24h: tokens?.input ?? 0,
    ai_output_tokens_24h: tokens?.output ?? 0,
    top_paths: top.results,
    requests_by_day: series.results,
  });
}

async function adminUsers(url: URL, env: Env): Promise<Response> {
  const q = (url.searchParams.get("q") || "").trim();
  const limit = Math.min(Number(url.searchParams.get("limit")) || 50, 200);
  const offset = Math.max(Number(url.searchParams.get("offset")) || 0, 0);
  const like = `%${q.replaceAll("%", "")}%`;
  const where = q
    ? "WHERE email LIKE ? OR username LIKE ? OR display_name LIKE ? OR id = ?"
    : "";
  const binds = q ? [like, like, like, q] : [];
  const [rows, total] = await Promise.all([
    env.DB.prepare(
      `SELECT * FROM users ${where} ORDER BY datetime(created_at) DESC LIMIT ? OFFSET ?`,
    )
      .bind(...binds, limit, offset)
      .all(),
    env.DB.prepare(`SELECT COUNT(*) AS n FROM users ${where}`)
      .bind(...binds)
      .first<{ n: number }>(),
  ]);
  return json({ users: rows.results, total: total?.n ?? 0, limit, offset });
}

async function adminUser(env: Env, id: string): Promise<Response> {
  const user = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(id).first();
  if (!user) return err(404, "RESOURCE_NOT_FOUND", "No such user");
  const [events, usage, ai] = await Promise.all([
    env.DB.prepare(
      "SELECT * FROM login_events WHERE user_id = ? ORDER BY created_at DESC LIMIT 40",
    )
      .bind(id)
      .all(),
    env.DB.prepare(
      `SELECT COUNT(*) AS n,
              COALESCE(SUM(CASE WHEN kind = 'ai' THEN 1 ELSE 0 END), 0) AS ai,
              COALESCE(SUM(input_tokens), 0) AS input_tokens,
              COALESCE(SUM(output_tokens), 0) AS output_tokens
       FROM api_usage WHERE user_id = ?`,
    )
      .bind(id)
      .first<{ n: number; ai: number; input_tokens: number; output_tokens: number }>(),
    env.DB.prepare(
      `SELECT path, COUNT(*) AS n FROM api_usage
       WHERE user_id = ? GROUP BY path ORDER BY n DESC LIMIT 8`,
    )
      .bind(id)
      .all(),
  ]);
  return json({
    user,
    login_events: events.results,
    usage: usage ?? { n: 0, ai: 0, input_tokens: 0, output_tokens: 0 },
    top_paths: ai.results,
  });
}

async function patchUser(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
  id: string,
): Promise<Response> {
  const existing = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<{
    id: string;
    is_active: number;
    display_name: string;
  }>();
  if (!existing) return err(404, "RESOURCE_NOT_FOUND", "No such user");
  let body: { is_active?: boolean; display_name?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return err(400, "BAD_REQUEST", "Body is not valid JSON");
  }
  const isActive = body.is_active === undefined ? existing.is_active : body.is_active ? 1 : 0;
  const displayName =
    body.display_name === undefined ? existing.display_name : String(body.display_name).slice(0, 80);
  await env.DB.prepare("UPDATE users SET is_active = ?, display_name = ? WHERE id = ?")
    .bind(isActive, displayName, id)
    .run();
  if (body.is_active === false) {
    await env.DB.prepare(
      `INSERT INTO login_events (user_id, event, source, user_agent, created_at)
       VALUES (?, 'disabled', 'admin', '', ?)`,
    )
      .bind(id, nowIso())
      .run();
  } else if (body.is_active === true && existing.is_active === 0) {
    await env.DB.prepare(
      `INSERT INTO login_events (user_id, event, source, user_agent, created_at)
       VALUES (?, 'enabled', 'admin', '', ?)`,
    )
      .bind(id, nowIso())
      .run();
  }
  const origin = (env.API_BASE_URL || "").replace(/\/$/, "");
  if (origin && (body.is_active !== undefined || body.display_name !== undefined)) {
    ctx.waitUntil(
      fetch(`${origin}/v1/internal/users/${id}`, {
        method: "PATCH",
        headers: {
          "content-type": "application/json",
          "x-novi-origin-secret": env.CONSOLE_ORIGIN_SECRET,
        },
        body: JSON.stringify({
          is_active: body.is_active,
          display_name: body.display_name,
        }),
      }).catch((error: unknown) => {
        log("console_origin_callback_failed", { error: String(error) });
      }),
    );
  }
  return adminUser(env, id);
}

async function adminUsage(url: URL, env: Env, userId?: string): Promise<Response> {
  const limit = Math.min(Number(url.searchParams.get("limit")) || 50, 200);
  const offset = Math.max(Number(url.searchParams.get("offset")) || 0, 0);
  const uid = userId || url.searchParams.get("user_id") || "";
  const path = url.searchParams.get("path") || "";
  const kind = url.searchParams.get("kind") || "";
  const from = url.searchParams.get("from") || "";
  const clauses: string[] = [];
  const binds: (string | number)[] = [];
  if (uid) {
    clauses.push("user_id = ?");
    binds.push(uid);
  }
  if (path) {
    clauses.push("path LIKE ?");
    binds.push(`%${path.replaceAll("%", "")}%`);
  }
  if (kind) {
    clauses.push("kind = ?");
    binds.push(kind);
  }
  if (from) {
    clauses.push("created_at >= ?");
    binds.push(from);
  }
  const where = clauses.length ? `WHERE ${clauses.join(" AND ")}` : "";
  const [rows, total] = await Promise.all([
    env.DB.prepare(
      `SELECT * FROM api_usage ${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    )
      .bind(...binds, limit, offset)
      .all(),
    env.DB.prepare(`SELECT COUNT(*) AS n FROM api_usage ${where}`)
      .bind(...binds)
      .first<{ n: number }>(),
  ]);
  return json({ events: rows.results, total: total?.n ?? 0, limit, offset });
}

async function readJson(request: Request): Promise<unknown> {
  return request.json();
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    try {
      if (request.method === "GET" && pathname === "/health") {
        return json({
          status: "ok",
          service: "novi-console",
          admin_password: env.ADMIN_PASSWORD ? "configured" : "missing",
          origin_secret: env.CONSOLE_ORIGIN_SECRET ? "configured" : "missing",
        });
      }

      if (pathname === "/api/ingest/account" && request.method === "POST") {
        const rejected = await requireOrigin(request, env);
        if (rejected) return rejected;
        return await ingestAccount(env, (await readJson(request)) as AccountBody);
      }
      if (pathname === "/api/ingest/usage" && request.method === "POST") {
        const rejected = await requireOrigin(request, env);
        if (rejected) return rejected;
        return await ingestUsage(env, (await readJson(request)) as UsageBody);
      }
      if (pathname.startsWith("/api/ingest/status/") && request.method === "GET") {
        const rejected = await requireOrigin(request, env);
        if (rejected) return rejected;
        return await userStatus(env, pathname.slice("/api/ingest/status/".length));
      }

      if (pathname === "/api/admin/login" && request.method === "POST") {
        return await adminLogin(request, env);
      }
      if (pathname === "/api/admin/logout" && request.method === "POST") {
        return await adminLogout(request, env);
      }

      const adminGate = await requireAdmin(request, env);
      if (pathname.startsWith("/api/admin/")) {
        if (adminGate) return adminGate;
        if (pathname === "/api/admin/me" && request.method === "GET") {
          return json({ ok: true });
        }
        if (pathname === "/api/admin/stats" && request.method === "GET") {
          return await adminStats(env);
        }
        if (pathname === "/api/admin/users" && request.method === "GET") {
          return await adminUsers(url, env);
        }
        if (pathname === "/api/admin/usage" && request.method === "GET") {
          return await adminUsage(url, env);
        }
        const userMatch = pathname.match(/^\/api\/admin\/users\/([^/]+)(\/usage)?$/);
        if (userMatch) {
          const id = decodeURIComponent(userMatch[1] ?? "");
          if (userMatch[2] === "/usage" && request.method === "GET") {
            return await adminUsage(url, env, id);
          }
          if (request.method === "GET") return await adminUser(env, id);
          if (request.method === "PATCH") return await patchUser(request, env, ctx, id);
        }
        return err(404, "RESOURCE_NOT_FOUND", "No such admin route");
      }

      return err(404, "RESOURCE_NOT_FOUND", "No such route");
    } catch (error) {
      console.error(JSON.stringify({ event: "console_unhandled", error: String(error) }));
      return err(500, "INTERNAL_ERROR", "Console failed");
    }
  },
} satisfies ExportedHandler<Env>;
