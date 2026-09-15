# novi-edge

A Cloudflare Worker that holds Novi's AI provider key, so the API server does
not have to.

```
iOS app ──▶ Novi API ──▶ novi-edge ──▶ provider
            (shared        (real key)
             secret)
```

## Why

The API already kept the provider key server-side, which is the important
part — it was never in the app bundle. But that put the key in the API
server's environment, so the key's blast radius was the whole origin: anything
that could read that process could spend the account.

This narrows it to one place. After deploying:

- The **provider key** exists only in Cloudflare's secret store, which does not
  read values back. The origin no longer has a copy.
- The API's `AI_API_KEY` becomes a **shared secret** — useful only for spending
  a capped daily budget through this Worker, not for talking to the provider.
- **Spend is capped at the edge**, before a request costs anything upstream.
- **Burst abuse is refused** before it reaches the provider.

It is not a substitute for the API's own authentication. Anyone holding the
shared secret can spend the budget, so it is still a key — just a much less
valuable one.

## Why no backend code changed

The Worker serves `POST /v1/messages` and speaks the provider's own error
dialect. That is exactly the path Novi's gateway already builds
(`{AI_BASE_URL}/messages`) and exactly the error shape it already parses — so
pointing the API here is two environment variables, not a refactor.

## Deploy

```bash
cd services/edge
npm install

npx wrangler kv namespace create EDGE_KV     # put the id in wrangler.jsonc
npx wrangler secret put PROVIDER_API_KEY     # the real upstream key
npx wrangler secret put EDGE_SHARED_SECRET   # openssl rand -base64 48
npx wrangler deploy
```

Then in the API's `.env`:

```
AI_BASE_URL=https://novi-edge.<your-subdomain>.workers.dev/v1
AI_API_KEY=<the same EDGE_SHARED_SECRET>
```

Delete the provider key from that file. That deletion is the point of all this.

## Local

```bash
cp .dev.vars.example .dev.vars   # fill in; gitignored
npm run dev                      # :8787
npm test                         # 17 tests, in workerd
npm run typecheck
```

`GET /health` reports whether each secret is **present**, never any part of its
value.

`worker-configuration.d.ts` is generated and committed, so a fresh clone
typechecks without a network round trip. Re-run `npm run types` after changing
a binding or a var in `wrangler.jsonc` — a hand-written `Env` drifts from the
config silently.

## Settings

Non-secret settings live in `wrangler.jsonc`:

| var | default | what it does |
|---|---|---|
| `PROVIDER_BASE_URL` | `https://1pkapi.com/v1` | upstream; `/messages` is appended |
| `CACHE_TTL_SECONDS` | `86400` | `0` disables caching entirely |
| `DAILY_REQUEST_CAP` | `2000` | UTC-day guard rail |
| `MAX_REQUEST_BYTES` | `262144` | bodies larger than this are refused unread |

## Two things worth knowing

**The cache keys on the whole request body.** Two learners only share an entry
when their entire prompt — context, question, everything — is byte-identical,
so nothing crosses between different inputs. The key is a SHA-256, so prompts
are not stored; the **responses** are, at the edge, for the TTL. Set
`CACHE_TTL_SECONDS` to `0` if that is not a trade you want. Creative requests
(`temperature > 0.3`) and streamed ones are never cached, and neither are
errors — caching a rate-limit reply would pin an outage in place for a day.

**The daily cap is a guard rail, not a ledger.** It is a KV read-then-write, and
KV is eventually consistent, so under concurrency a few extra requests get
through. That is deliberate: this exists to stop a runaway loop or a leaked
secret, and a Durable Object would add a stateful hop to every request to make
a number exact that nobody bills against.
