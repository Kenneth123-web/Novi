import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";

const ORIGIN = "test-origin-secret";
const ADMIN = "test-admin-password";

async function run(request: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

function originHeaders(extra: Record<string, string> = {}): Record<string, string> {
  return { "content-type": "application/json", "x-novi-origin-secret": ORIGIN, ...extra };
}

function ingestAccount(body: Record<string, unknown>): Request {
  return new Request("https://console.test/api/ingest/account", {
    method: "POST",
    headers: originHeaders(),
    body: JSON.stringify(body),
  });
}

function ingestUsage(body: Record<string, unknown>): Request {
  return new Request("https://console.test/api/ingest/usage", {
    method: "POST",
    headers: originHeaders(),
    body: JSON.stringify(body),
  });
}

async function signIn(): Promise<string> {
  const response = await run(
    new Request("https://console.test/api/admin/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ password: ADMIN }),
    }),
  );
  expect(response.status).toBe(200);
  const cookie = response.headers.get("set-cookie") ?? "";
  const match = cookie.match(/novi_console=([^;]+)/);
  expect(match).toBeTruthy();
  return match?.[1] ?? "";
}

function admin(path: string, token: string, init: RequestInit = {}): Request {
  return new Request(`https://console.test${path}`, {
    ...init,
    headers: {
      cookie: `novi_console=${token}`,
      ...(init.body ? { "content-type": "application/json" } : {}),
      ...(init.headers ?? {}),
    },
  });
}

const sample = {
  id: "11111111-1111-1111-1111-111111111111",
  email: "ada@example.com",
  username: "ada",
  display_name: "Ada",
  event: "registered",
  source: "register",
};

beforeEach(async () => {
  await env.DB.exec(
    "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, email TEXT NOT NULL UNIQUE, username TEXT NOT NULL, display_name TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1, is_admin INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT 'register', created_at TEXT NOT NULL, last_seen_at TEXT, last_login_at TEXT, login_count INTEGER NOT NULL DEFAULT 0);",
  );
  await env.DB.exec(
    "CREATE TABLE IF NOT EXISTS login_events (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, event TEXT NOT NULL, source TEXT NOT NULL DEFAULT '', user_agent TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL);",
  );
  await env.DB.exec(
    "CREATE TABLE IF NOT EXISTS api_usage (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT, method TEXT NOT NULL, path TEXT NOT NULL, status INTEGER NOT NULL, latency_ms REAL NOT NULL DEFAULT 0, request_id TEXT, kind TEXT NOT NULL DEFAULT 'http', model TEXT, input_tokens INTEGER, output_tokens INTEGER, created_at TEXT NOT NULL);",
  );
  await env.DB.exec(
    "CREATE TABLE IF NOT EXISTS admin_sessions (token_hash TEXT PRIMARY KEY, created_at TEXT NOT NULL, expires_at TEXT NOT NULL);",
  );
  await env.DB.exec(
    "DELETE FROM api_usage; DELETE FROM login_events; DELETE FROM users; DELETE FROM admin_sessions;",
  );
});

afterEach(() => {
  // D1 is wiped in beforeEach.
});

describe("health", () => {
  it("reports that secrets are present, never their values", async () => {
    const response = await run(new Request("https://console.test/health"));
    expect(response.status).toBe(200);
    const body = (await response.json()) as { admin_password: string };
    expect(body.admin_password).toBe("configured");
    const text = JSON.stringify(body);
    expect(text).not.toContain(ADMIN);
    expect(text).not.toContain(ORIGIN);
  });
});

describe("ingest", () => {
  it("rejects a caller with no origin secret", async () => {
    const response = await run(
      new Request("https://console.test/api/ingest/account", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(sample),
      }),
    );
    expect(response.status).toBe(401);
  });

  it("stores an account and login event", async () => {
    const created = await run(ingestAccount(sample));
    expect(created.status).toBe(204);

    const status = await run(
      new Request(`https://console.test/api/ingest/status/${sample.id}`, {
        headers: originHeaders(),
      }),
    );
    expect(status.status).toBe(200);
    const body = (await status.json()) as { is_active: boolean; known: boolean };
    expect(body.is_active).toBe(true);
    expect(body.known).toBe(true);
  });

  it("records usage against a user", async () => {
    await run(ingestAccount(sample));
    const response = await run(
      ingestUsage({
        user_id: sample.id,
        method: "GET",
        path: "/v1/feed",
        status: 200,
        latency_ms: 12.5,
        kind: "http",
      }),
    );
    expect(response.status).toBe(204);
  });

  it("a later login ingest does not re-enable a disabled account", async () => {
    await run(ingestAccount(sample));
    const token = await signIn();
    const disabled = await run(
      admin(`/api/admin/users/${sample.id}`, token, {
        method: "PATCH",
        body: JSON.stringify({ is_active: false }),
      }),
    );
    expect(disabled.status).toBe(200);

    await run(ingestAccount({ ...sample, event: "logged_in", source: "login", is_active: true }));
    const status = await run(
      new Request(`https://console.test/api/ingest/status/${sample.id}`, {
        headers: originHeaders(),
      }),
    );
    const body = (await status.json()) as { is_active: boolean };
    expect(body.is_active).toBe(false);
  });
});

describe("admin", () => {
  it("rejects the wrong password", async () => {
    const response = await run(
      new Request("https://console.test/api/admin/login", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ password: "nope" }),
      }),
    );
    expect(response.status).toBe(401);
    const text = await response.text();
    expect(text).not.toContain(ADMIN);
  });

  it("lists users, stats and usage after sign-in", async () => {
    await run(ingestAccount(sample));
    await run(
      ingestUsage({
        user_id: sample.id,
        method: "POST",
        path: "/v1/ask",
        status: 200,
        kind: "ai",
        model: "grok-4.6",
        input_tokens: 80,
        output_tokens: 40,
        latency_ms: 1200,
      }),
    );
    const token = await signIn();

    const users = await run(admin("/api/admin/users", token));
    expect(users.status).toBe(200);
    const listed = (await users.json()) as { total: number; users: { email: string }[] };
    expect(listed.total).toBe(1);
    expect(listed.users[0]?.email).toBe("ada@example.com");

    const stats = await run(admin("/api/admin/stats", token));
    const numbers = (await stats.json()) as { users: number; ai_output_tokens_24h: number };
    expect(numbers.users).toBe(1);
    expect(numbers.ai_output_tokens_24h).toBe(40);

    const usage = await run(admin("/api/admin/usage?kind=ai", token));
    const events = (await usage.json()) as { total: number };
    expect(events.total).toBe(1);

    const me = await run(admin(`/api/admin/users/${sample.id}`, token));
    const detail = (await me.json()) as { usage: { output_tokens: number } };
    expect(detail.usage.output_tokens).toBe(40);
  });

  it("search finds a user by email fragment", async () => {
    await run(ingestAccount(sample));
    const token = await signIn();
    const response = await run(admin("/api/admin/users?q=ada@", token));
    const body = (await response.json()) as { total: number };
    expect(body.total).toBe(1);
  });
});
