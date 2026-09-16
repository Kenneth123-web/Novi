# novi-console

A Cloudflare Worker that stores Novi's accounts, login events and API usage,
and serves the admin site that reads them.

```
iOS app ──▶ Novi API ──▶ novi-console (D1 + this site)
                 │              ▲
                 └──────────────┘  ingest / status
```

Passwords and JWTs stay on the FastAPI origin — they sit next to the learning
data, and Argon2 plus rotating refresh tokens already live there. What this
Worker holds is the **ledger**: who exists, when they signed in, whether an
operator has disabled them, and every API/AI call the origin reports.

The HTML in `public/` is the admin site. `/api/*` and `/health` run in the
Worker first; everything else is a static asset.

## Why a Worker, not a table on the origin

The origin is a laptop (today) and a single Postgres (always). Putting the
operator view on Cloudflare means:

- Account and usage rows survive the origin being wiped and re-seeded.
- Disabling a user is a D1 write the next login consults, even if Postgres
  has not caught up.
- The site is on the same hostname as the ledger. There is no second CORS
  origin and no admin cookie on the public API.

It is not a substitute for the API's own authentication. The iOS app still
calls `POST /v1/auth/login`. `POST /v1/auth/dev-skip` is how a developer
lands in the product without a password; this Worker then records that as
`source = dev-skip`.

## Deploy

Use the Cloudflare account already logged in on **this machine**
(`npx wrangler whoami`). Do not paste another project's `account_id` into
`wrangler.jsonc`.

```bash
cd services/console
npm install

npx wrangler d1 create novi-console   # put the id in wrangler.jsonc
npx wrangler d1 migrations apply novi-console --remote
npx wrangler secret put ADMIN_PASSWORD
npx wrangler secret put CONSOLE_ORIGIN_SECRET   # openssl rand -base64 48
npx wrangler deploy
```

Then in the API's `.env`:

```
CONSOLE_BASE_URL=https://novi-console.<your-subdomain>.workers.dev
CONSOLE_ORIGIN_SECRET=<the same secret>
```

Open the Worker URL, sign in with `ADMIN_PASSWORD`. You can list users,
disable logins, and read API/AI usage.

## Local

```bash
cp .dev.vars.example .dev.vars   # fill in; gitignored
npx wrangler d1 migrations apply novi-console --local
npm run dev                      # :8787
npm test
npm run typecheck
```

`GET /health` reports whether each secret is **present**, never any part of
its value.

`worker-configuration.d.ts` is generated and committed. Re-run `npm run types`
after changing a binding or a var in `wrangler.jsonc`.

## Origin protocol

The Novi API authenticates ingest with `X-Novi-Origin-Secret`.

| method | path | body |
|---|---|---|
| POST | `/api/ingest/account` | `{id, email, username, display_name, event, source, ...}` |
| POST | `/api/ingest/usage` | `{user_id, method, path, status, kind, ...}` |
| GET | `/api/ingest/status/:id` | `{is_active, known}` |

Admin routes sit under `/api/admin/*` and use an HttpOnly session cookie
issued by `POST /api/admin/login`.

Disabling a user writes D1 immediately. If `API_BASE_URL` is set, the Worker
also PATCHes the origin so Postgres `is_active` and refresh tokens match.
Login on the origin consults D1 as well, and **fails open** if the Worker is
unreachable — an outage of this ledger must not lock every learner out.
