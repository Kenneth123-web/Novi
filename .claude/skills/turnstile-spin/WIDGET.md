# Novi Turnstile widget

Public metadata only. The widget secret is a Worker secret
(`TURNSTILE_SECRET_KEY` on `turnstile-siteverify-novi`) and is not stored here.

| Field | Value |
|---|---|
| Account | `f7b9ca991f7981a64e78b60dce9d2b0a` |
| Widget name | Novi (Spin) |
| Sitekey | `0x4AAAAAAE5j-PpNPgTtBBtz` |
| Mode | managed |
| Domains | `localhost`, `127.0.0.1`, `novi-console.rememberly-kenneth.workers.dev` |
| Worker | `turnstile-siteverify-novi` |
| Worker URL | `https://turnstile-siteverify-novi.rememberly-kenneth.workers.dev` |
| iOS widget host | `https://novi-console.rememberly-kenneth.workers.dev/turnstile` |
| `data-action` | `turnstile-spin-v1` |

FastAPI calls the Worker (`TURNSTILE_SITEVERIFY_URL`). iOS and the console
only ever send the token; they never hold the secret.
