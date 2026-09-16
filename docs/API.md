# API

Base URL `<host>/v1`. Interactive schema at `/docs`, machine-readable at
`/openapi.json` — those are generated from the code and are the authority. This
page covers the contract and the conventions around it.

## Conventions

**Auth.** `Authorization: Bearer <access_token>`. Rotate with
`POST /auth/refresh`; presenting a refresh token consumes it.

**Errors.** One shape, every status code:

```json
{"error": {"code": "AI_UNAVAILABLE",
           "message": "The AI tutor is temporarily unavailable",
           "details": {"reason": "capacity"},
           "request_id": "9f3c1ab2de77c401"}}
```

`code` is stable and safe to branch on. `message` is written for a person.
`details` carries `fields: [{field, reason}]` for body validation and a single
`field` for service-level validation. Stack traces never appear.

| code | status | meaning |
|---|---|---|
| `VALIDATION_ERROR` | 422 | request failed validation |
| `UNAUTHORIZED` / `TOKEN_INVALID` | 401 | sign in again |
| `INVALID_CREDENTIALS` | 401 | wrong email or password |
| `RESOURCE_NOT_FOUND` | 404 | no such thing |
| `ALREADY_EXISTS` / `ALREADY_SUBMITTED` | 409 | uniqueness or state conflict |
| `RATE_LIMITED` | 429 | see `details.window_seconds` |
| `AI_UNAVAILABLE` | 503 | gateway down or out of capacity; see `details.reason` |
| `INTERNAL_ERROR` | 500 | our fault |

`AI_UNAVAILABLE` is deliberately not a 500. `details.reason` is one of
`missing_api_key`, `capacity`, `upstream_error`, `transport`, `malformed`,
`unparseable`, `too_few_valid` — enough for the client to tell "come back
later" apart from "this is misconfigured".

**Rate limits**, per user when authenticated and per IP otherwise. Keying an
authenticated limit by IP would make one school's NAT share a single AI budget.

| bucket | limit |
|---|---|
| `ai` (`/ask`, `/quiz`, summarise, translate) | 20/min |
| `search` | 60/min |
| `auth` | 10/min |
| writes | 120/min |

## Endpoints

### Auth
`POST /auth/register` · `POST /auth/login` · `POST /auth/dev-skip` ·
`POST /auth/refresh` · `POST /auth/logout` · `GET /auth/session`

Passwords are 8–128 characters and may not be all letters or all digits. Login
runs the Argon2 verify even for an unknown email, against a dummy hash —
skipping it makes "no such account" measurably faster than "wrong password",
which is a working account-enumeration oracle.

`POST /auth/dev-skip` issues a real session for the reserved developer account
(`developer@novi.app`). In development and test it is open. In production the
route 404s unless `DEV_SKIP_SECRET` is set, and then the body must carry that
secret. It is not a fake phase: the tokens are the same shape login returns.

### Profile
`GET /me` · `PATCH /me` · `POST /onboarding` ·
`GET /onboarding/options` · `GET /me/history?days=14`

Onboarding submits the whole questionnaire once. `grade` and
`weak_subject_slugs` are required: they are what the ranker and the tutor
read. `subject_slugs` order is priority and is preserved: the first subject
leads the feed and gets the highest starting interest weight. `weak_subject_slugs`
must be a subset of `subject_slugs`. `PATCH /me` with `subject_slugs` keeps
existing weights for subjects already present — re-seeding would wipe interest
the learner earned by using the app.

### Catalog
`GET /subjects` · `GET /concepts?subject_slug=` · `GET /concepts/{id}`

`GET /concepts/{id}` returns the concept, its subject, and `next` — the
outgoing edges of the concept graph, falling back to same-subject siblings at a
similar level so the strip is never empty.

### Feed and content
`GET /feed?limit=&offset=&subject=` · `GET /content/{id}` ·
`POST /content/{id}/save` · `DELETE /content/{id}/save` ·
`POST /content/{id}/like` · `DELETE /content/{id}/like` · `GET /saved` ·
`POST /interactions`

Feed items carry `score`, `reason`, `is_saved` and `is_liked`, so the client
renders its own buttons correctly without N extra round trips.

`POST /interactions` is the single behaviour write. One endpoint rather than
one per event type: a new signal should not need a new route and a new client
release before it can be collected. Valid `kind` values are listed in
`INTERACTION_TYPES`; an unknown one is a 422 with the allowed list.

### Ask and discovery
`POST /ask` · `GET /questions` · `POST /questions/{id}/feedback` ·
`GET /search?q=` · `GET /discussions` · `GET /discussions/{id}` ·
`POST /discussions/{id}/summarize` · `POST /discussions/{id}/translate`

`POST /ask` returns the explanation **and** the discovery rail — watch, read,
discuss, related concepts — in one response. A second round trip would put a
spinner exactly where the learner's momentum is.

`GET /search` deliberately does not call the model. Search has to be instant,
and the explanation is one tap away on the returned concept card.

Summaries and translations are cached on the discussion row. Both are expensive
and neither changes once the thread is fetched.

### Learning and passport
`POST /quiz` · `POST /quiz/{id}/submit` · `GET /passport` ·
`POST /passport/learn` · `GET /projects` · `POST /projects` ·
`PATCH /projects/{id}`

Quiz questions come back without `correct_index`. Submitting returns the key
alongside the grading. Unanswered questions count as wrong — otherwise a
learner masters a concept by answering one of five. A quiz cannot be submitted
twice.

`POST /passport/learn` lets a learner assert they know something. It stops at
`learned` and cannot reach `mastered`: self-reporting is weaker evidence than a
quiz.

Both return `new_stamps` containing only what *this* request earned, so the
client plays the celebration once rather than every time the passport opens.

### Tutorial ingest
`POST /internal/ingest` (origin secret) or `./scripts/dev.sh ingest`.

Pulls real tutorials from YouTube, Reddit, X, and MediaCrawler platforms
(Bilibili search live; Xiaohongshu/Douyin/Zhihu via MediaCrawler JSON dumps in
`MEDIACRAWLER_DATA_DIR`). Matched rows are stored `is_sample=false` with the
source URL. Unmatched titles are dropped, not forced onto a random concept.
