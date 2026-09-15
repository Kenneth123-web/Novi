# Architecture

## Shape

```
            iPhone (SwiftUI)
                  │  HTTPS, Bearer JWT
                  ▼
          services/api (FastAPI)
                  │
   ┌──────────────┼──────────────┐
   ▼              ▼              ▼
PostgreSQL   AI gateway      ranking
             (Gemini)
```

One client, on purpose. Every surface in the plan — feed, explore, ask,
passport, profile — is reachable on a phone, and one finished client beats two
half-built ones.

## The API key boundary

The app never holds a provider key. It calls `POST /v1/ask`; the server calls
the provider. This is the single most important structural decision in the
repo: a key shipped in an iOS binary is a key anybody with a copy of that
binary can extract, and it cannot be rotated without an App Store release.

`novi/ai/gateway.py` is the only module in the API that knows a key exists.
Everything above it receives a parsed dict or an `AIUnavailable`.

**One layer further out**, `services/edge` is a Cloudflare Worker that holds
the real provider key and accepts a shared secret in its place. With it
deployed the origin keeps no copy at all, so compromising the API server
yields a credential that can only spend a capped daily budget through one
endpoint — not the provider account.

The Worker serves `POST /v1/messages` and returns the provider's own error
shape. That is not a coincidence: it is exactly what the gateway already
builds and already parses, so the boundary moved without a line of backend
code changing. Two environment variables switch it on.

The gateway is protocol-agnostic for the same reason. `AI_PROTOCOL=anthropic`
sends `POST /v1/messages` with `x-api-key`; `openai` sends
`/v1/chat/completions` with a bearer token. Against the configured gateway the
native path answers in ~38s with a structured transient error where the OpenAI
path hangs for 240s, which is the whole argument for making it a setting.

## Layering

```
routers/     HTTP only — parse, authorise, delegate, serialise
services/    business logic; owns the rules
models/      SQLAlchemy tables
schemas/     Pydantic request/response types
core/        errors, logging, security, deps, rate limits
ai/          gateway + versioned prompts
```

A router never builds a query and a service never touches `Request`. That earns
its keep the first time logic has to run somewhere that is not an HTTP request
— the seeder calls services directly, and an ingestion worker will too.

## Decisions

**One error shape.** Every failure at every status code returns
`{"error": {code, message, details?, request_id?}}`. The client has exactly one
error path. Unhandled exceptions collapse to `INTERNAL_ERROR` with the real
cause in the log under the same `request_id`.

**`AI_UNAVAILABLE` is not a 500.** The tutor being down and the product being
broken are different facts, and the app renders them differently: a 503 with
`details.reason` produces a "tutor is offline" panel that says search and the
feed still work. A generic error would imply the whole app had failed.

**Mastery only moves forward.** `discovered → viewed → explored → practiced →
learned → mastered`. Without the monotonic rule, mastering a concept and later
scrolling past a video about it would demote it, and the recommender would
start re-teaching what the learner knows. Only a quiz can push past
`practiced`, because only a quiz is evidence of understanding rather than
exposure.

**Ranking is deterministic and explainable.** Weighted components, no learned
model. Every number can be explained, the "why this?" line on a card is
computed from the same components that produced the rank, and a smarter model
later needs a baseline to beat. The load-bearing term is `gap`: interest alone
converges on showing people what they already know.

**Search widens rather than failing.** All terms, then any term, then
substring. The index uses Postgres's `simple` configuration because the store
is mixed Chinese and English and the English stemmer mangles Chinese titles —
which means stopwords are kept, which means "how do derivatives work" ANDs four
words and matches nothing. Two tests cover exactly that.

**Refresh is serialised on the client.** Refresh tokens rotate server-side, so
several requests each noticing a stale token at launch would all refresh, and
the first to land would invalidate the rest — signing the user out on launch.
`APIClient` shares one in-flight refresh `Task`.

## Client structure

```
Novi/
  App/         entry, phase gate, tab bar, demo arguments
  Core/        APIClient, APIError, TokenStore, AppSession
  Design/      NV.swift — every colour, space, radius, type step
  Components/  Waterfall, FlowRow, GeneratedArt, Controls
  Model/       DTOs
  Features/    Auth · Onboarding · Home · Explore · Ask · Detail ·
               Passport · Profile · Quiz
```

`AppSession.phase` is a four-case enum — `launching`, `signedOut`,
`onboarding`, `ready` — and `RootView` switches on it and nothing else. The
states are mutually exclusive by construction, so it is not possible to render
a personalised feed for somebody who has no profile to personalise it from.

## Phase status

| Phase | State |
|---|---|
| 1 · Foundation | done — monorepo, schema, auth, error/log/rate-limit core, client API layer |
| 2 · Onboarding | done — five steps, ordered subject priority, one submit |
| 3 · Feed | done — ranked feed, masonry, paging, save/like, content detail |
| 4 · AI | done — gateway, structured answers, prompt versioning; blocked on gateway capacity for live output |
| 5 · Discovery | done — search, related content, discussions, translate, summarise |
| 6 · Learning | done — quizzes, mastery, history, concept tracking |
| 7 · Passport | done — overview, stamps, subject progress; projects exist in the API but have no screen |
| 8 · Polish | partial — skeletons, empty and error states, animations; no dark mode, no client tests |
