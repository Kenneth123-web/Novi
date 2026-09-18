import { env, createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";

const SECRET = "test-shared-secret";

function ask(
  body: unknown,
  headers: Record<string, string> = {},
  path = "/v1/messages",
): Request {
  const payload = JSON.stringify(body);
  return new Request(`https://edge.test${path}`, {
    method: "POST",
    headers: {
      "x-api-key": SECRET,
      "content-type": "application/json",
      "content-length": String(new TextEncoder().encode(payload).length),
      ...headers,
    },
    body: payload,
  });
}

async function run(request: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

/** A successful provider reply, in the Anthropic shape. */
function providerOK(text = '{"summary":"ok"}') {
  return new Response(
    JSON.stringify({ content: [{ type: "text", text }], usage: { input_tokens: 5, output_tokens: 3 } }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}

beforeEach(async () => {
  // KV persists across tests in the same worker; the budget counter would
  // otherwise leak from one case into the next.
  const keys = await env.EDGE_KV.list();
  await Promise.all(keys.keys.map((k) => env.EDGE_KV.delete(k.name)));
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe("auth", () => {
  it("rejects a caller with no shared secret", async () => {
    const response = await run(ask({ model: "m" }, { "x-api-key": "" }));
    expect(response.status).toBe(401);
    const body = (await response.json()) as { error: { type: string } };
    expect(body.error.type).toBe("authentication_error");
  });

  it("rejects a wrong secret of the same length", async () => {
    // Same length on purpose: a length check would pass this, so it proves
    // the comparison looks at the bytes.
    const response = await run(ask({ model: "m" }, { "x-api-key": "test-shared-secrex" }));
    expect(response.status).toBe(401);
  });

  it("never echoes either secret back", async () => {
    const response = await run(ask({ model: "m" }, { "x-api-key": "wrong" }));
    const text = await response.text();
    expect(text).not.toContain("sk-test-provider-key");
    expect(text).not.toContain(SECRET);
  });
});

describe("forwarding", () => {
  it("swaps the shared secret for the provider key", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());

    await run(ask({ model: "claude-haiku-4-5", temperature: 0 }));

    expect(fetchSpy).toHaveBeenCalledOnce();
    const [url, init] = fetchSpy.mock.calls[0]! as [string, RequestInit];
    expect(url).toBe("https://1pkapi.com/v1/messages");
    const sent = new Headers(init.headers);
    // The whole point of the Worker, as an assertion.
    expect(sent.get("x-api-key")).toBe("sk-test-provider-key");
    expect(sent.get("x-api-key")).not.toBe(SECRET);
  });

  it("passes the body through untouched", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());
    const payload = { model: "m", system: "RULES", messages: [{ role: "user", content: "q" }] };

    await run(ask(payload));

    const [, init] = fetchSpy.mock.calls[0]! as [string, RequestInit];
    expect(JSON.parse(init.body as string)).toEqual(payload);
  });

  it("reports an unreachable provider as a provider-shaped error", async () => {
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("boom"));
    const response = await run(ask({ model: "m" }));
    expect(response.status).toBe(502);
    const body = (await response.json()) as { type: string; error: { type: string } };
    expect(body.type).toBe("error");
    expect(body.error.type).toBe("api_error");
  });
});

describe("cache", () => {
  it("serves an identical deterministic request from KV", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());

    const first = await run(ask({ model: "m", temperature: 0, messages: [{ role: "user", content: "why" }] }));
    expect(first.headers.get("x-novi-edge")).toBe("miss");

    const second = await run(ask({ model: "m", temperature: 0, messages: [{ role: "user", content: "why" }] }));
    expect(second.headers.get("x-novi-edge")).toBe("hit");
    expect(fetchSpy).toHaveBeenCalledOnce();
    expect(await second.text()).toContain("summary");
  });

  it("stores cache entries as ciphertext, not the provider body", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());
    await run(ask({ model: "m", temperature: 0, messages: [{ role: "user", content: "why" }] }));

    const keys = await env.EDGE_KV.list();
    const cached = keys.keys.find((k) => k.name.startsWith("ai:"));
    expect(cached).toBeTruthy();
    const stored = await env.EDGE_KV.get(cached!.name);
    expect(stored?.startsWith("nv1.")).toBe(true);
    expect(stored).not.toContain("summary");
  });

  it("does not let a different prompt hit another prompt's entry", async () => {
    // A fresh Response per call: a Response body can only be read once, and a
    // single mocked instance returned twice leaves the second read on an
    // already-consumed stream.
    vi.spyOn(globalThis, "fetch").mockImplementation(async () => providerOK());
    await run(ask({ model: "m", temperature: 0, messages: [{ role: "user", content: "a" }] }));

    const other = await run(ask({ model: "m", temperature: 0, messages: [{ role: "user", content: "b" }] }));
    expect(other.headers.get("x-novi-edge")).toBe("miss");
  });

  it("does not cache a creative request", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => providerOK());
    const payload = { model: "m", temperature: 0.9, messages: [{ role: "user", content: "q" }] };

    await run(ask(payload));
    await run(ask(payload));

    // The caller asked for variety; handing back a stored answer removes it.
    expect(fetchSpy).toHaveBeenCalledTimes(2);
  });

  it("does not cache an error, so an outage is not pinned in place", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(
      async () =>
        new Response(
          JSON.stringify({ type: "error", error: { type: "rate_limit_error", message: "nope" } }),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
    );
    const payload = { model: "m", temperature: 0, messages: [{ role: "user", content: "q" }] };

    await run(ask(payload));
    await run(ask(payload));

    expect(fetchSpy).toHaveBeenCalledTimes(2);
  });
});

describe("budget", () => {
  it("refuses once the day's cap is reached, without calling the provider", async () => {
    await env.EDGE_KV.put(`budget:${new Date().toISOString().slice(0, 10)}`, "2000");
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());

    const response = await run(ask({ model: "m", temperature: 0.9 }));

    expect(response.status).toBe(429);
    const body = (await response.json()) as { error: { type: string } };
    // Reported as a rate limit so the Novi backend maps it to its existing
    // "the tutor is temporarily unavailable" state.
    expect(body.error.type).toBe("rate_limit_error");
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("counts a forwarded request against the day", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());
    await run(ask({ model: "m", temperature: 0.9 }));

    const used = await env.EDGE_KV.get(`budget:${new Date().toISOString().slice(0, 10)}`);
    expect(used).toBe("1");
  });

  it("does not spend budget on a cache hit", async () => {
    vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());
    const payload = { model: "m", temperature: 0, messages: [{ role: "user", content: "q" }] };

    await run(ask(payload));
    await run(ask(payload));

    const key = `budget:${new Date().toISOString().slice(0, 10)}`;
    expect(await env.EDGE_KV.get(key)).toBe("1");
  });
});

describe("limits and routing", () => {
  it("refuses an oversized body before reading it", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockResolvedValue(providerOK());
    const response = await run(ask({ model: "m" }, { "content-length": "999999" }));

    expect(response.status).toBe(413);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  it("rejects a body that is not JSON", async () => {
    const response = await run(
      new Request("https://edge.test/v1/messages", {
        method: "POST",
        headers: { "x-api-key": SECRET, "content-type": "application/json" },
        body: "not json",
      }),
    );
    expect(response.status).toBe(400);
  });

  it("reports health without revealing any secret", async () => {
    const response = await run(new Request("https://edge.test/health"));
    const text = await response.text();

    expect(response.status).toBe(200);
    expect(text).toContain('"status":"ok"');
    expect(text).not.toContain("provider_key");
    expect(text).not.toContain("shared_secret");
    expect(text).not.toContain("sk-test-provider-key");
    expect(text).not.toContain(SECRET);
  });

  it("404s an unknown route in the provider's error shape", async () => {
    const response = await run(new Request("https://edge.test/v1/embeddings", { method: "POST" }));
    expect(response.status).toBe(404);
    const body = (await response.json()) as { type: string };
    expect(body.type).toBe("error");
  });
});

describe("openai protocol", () => {
  const OPENAI = "/v1/chat/completions";

  it("accepts the shared secret as a bearer token", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => providerOK());

    const request = ask({ model: "grok-4.6" }, { "x-api-key": "", authorization: `Bearer ${SECRET}` }, OPENAI);
    const response = await run(request);

    expect(response.status).toBe(200);
    expect(fetchSpy).toHaveBeenCalledOnce();
  });

  it("forwards to /chat/completions with a bearer provider key", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => providerOK());

    await run(ask({ model: "grok-4.6", temperature: 0 }, {}, OPENAI));

    const [url, init] = fetchSpy.mock.calls[0]! as [string, RequestInit];
    expect(url).toBe("https://1pkapi.com/v1/chat/completions");
    const sent = new Headers(init.headers);
    // The swap, on the other protocol.
    expect(sent.get("authorization")).toBe("Bearer sk-test-provider-key");
    expect(sent.get("authorization")).not.toContain(SECRET);
  });

  it("keys the cache per protocol", async () => {
    const fetchSpy = vi.spyOn(globalThis, "fetch").mockImplementation(async () => providerOK());
    const payload = { model: "m", temperature: 0, messages: [{ role: "user", content: "q" }] };

    await run(ask(payload, {}, "/v1/messages"));
    const other = await run(ask(payload, {}, OPENAI));

    // Same bytes, different wire shape: sharing one entry would hand a caller
    // a body it cannot parse.
    expect(other.headers.get("x-novi-edge")).toBe("miss");
    expect(fetchSpy).toHaveBeenCalledTimes(2);
  });
});
