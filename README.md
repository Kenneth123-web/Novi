# Novi

An AI social learning app. A personalised feed of educational content, a tutor
that explains what you're stuck on, and a passport that records what you
actually learned.

One client — a SwiftUI iOS app — on a FastAPI backend with PostgreSQL.

The loop the product is built around:

```
feed → open something → "I have a question" → explanation
     → watch / read / discuss → quiz → concept learned → passport
     → better feed
```

```
apps/mobile/       SwiftUI client (iOS 17+)
services/api/      FastAPI — the only thing that talks to the database or to Gemini
database/          Migrations and seed data
docs/              Architecture, database, API
scripts/dev.sh     Every command below, in one place
```

## Run it

Needs `uv`, `xcodegen`, Xcode, and PostgreSQL 17:

```bash
brew install postgresql@17 xcodegen uv
brew services start postgresql@17
```

Then:

```bash
./scripts/dev.sh setup     # venv, database, migrations, seed data
./scripts/dev.sh api       # API on :8000
./scripts/dev.sh ios       # regenerate the Xcode project and build
```

`setup` writes a `.env` from `.env.example`. Put your gateway key in it:

```
AI_API_KEY=sk-...
AI_BASE_URL=https://1pkapi.com/v1
AI_PROTOCOL=anthropic
AI_MODEL=claude-haiku-4-5
```

`AI_PROTOCOL=anthropic` sends `POST /v1/messages` with `x-api-key` — the shape
`@ai-sdk/anthropic` uses. Set it to `openai` for a gateway that only speaks
`/v1/chat/completions`. Against 1pkapi the native endpoint is measurably
healthier: it answers in ~38s with a structured, transient `rate_limit_error`
where the OpenAI path hangs for 240s.

`AI_MODEL` names the model you *want*. If the gateway will not serve it the
request walks `AI_MODEL_FALLBACKS` and uses the first one that is served,
remembering the refusal so the chain costs one wasted call rather than one per
request. That is why Haiku is the default even though this gateway does not
carry it yet.

**The key never reaches the client.** The app calls `POST /v1/ask` and the API
calls Gemini. A key in an app bundle is a key anyone with the bundle can
extract. `.env` is gitignored; nothing in `apps/mobile` reads it.

The simulator shares the host's loopback, so the app finds the API at
`127.0.0.1:8000` with no configuration. A device build needs the host's LAN
address — pass `-apiBaseURL http://192.168.x.x:8000/v1`.

## Design

The visual system is ported from the Travelers app's: a long neutral ink
scale carries the hierarchy, the page is a near-white that is not the card
white, and Instrument Sans (SIL Open Font License) is bundled rather than
left to the system face.

**The scale is golden.** Type is `15 × φ^(n/6)` — sixths, because a full φ
jump between adjacent sizes is far too coarse for a UI ramp, but every sixth
step is still an exact golden multiple of the body: 15 → 24.27 → 39.27.
Spacing is Fibonacci (5, 8, 13, 21, 34, 55), the integer approximation of the
same ratio, so type and space agree without either being bent to fit.

**Two densities, on purpose.** Arrival screens — launch, sign-in, onboarding,
the passport cover — run at a 21pt page margin with large type; they have
nothing to scan and this is where the product makes its case. Browse screens —
feed, search results, saved — drop to an 8pt gutter and the card title falls a
step, which puts the column width at ~184pt, the same as Rednote's. At a 21pt
margin a two-column feed wastes about a sixth of the screen on nothing.

One rule does most of the work: **the accent is not the button colour.**
Primary actions are near-black. Violet appears in three places — Ask, an
active state, an earned stamp — which is the whole reason it reads as meaning
rather than decoration. Adding it to a second kind of control undoes this.

The opening is an animated mark: six nodes appear in sequence and the edges
between them draw themselves. The mark is the product's own data structure —
a concept graph — so it is the thesis rather than a logo.
`-demoHoldIntro YES` stops on the finished frame, because the sequence is
shorter than a `simctl` screenshot round trip and is otherwise the one screen
that cannot be captured.

Screen mockups live in `design/canvas/` as a Claude Design canvas; re-seed
them with the helper and republish to update the shared link.

## Checks

```bash
./scripts/dev.sh check     # ruff + pytest + migration parity
```

Tests run against a real Postgres (`novi_test`), not SQLite: the schema uses
JSONB, arrays, a generated tsvector column and Postgres full-text search, and a
suite that passes on a database the product never runs on proves very little.
The test schema is built by running the *migrations*, so a migration that does
not apply fails the test run rather than the deploy.

## What is real and what is a stand-in

**The content store is seeded with generated placeholders.** Every row is
written `is_sample = true` and the client draws a "Sample" marker on it. Creator
handles are invented and generic, and no URLs are fabricated — a plausible
bilibili link that 404s invites a tap, and a post credited to a real account
would be a fake record about a real party. Replace `database/seeds/content.py`
with a real ingestion pipeline and the flag goes away on its own.

**Cover images are drawn, not fetched.** There are no photographs behind this
feed, and a grid of grey rectangles reads as a broken image rather than as a
layout. Each cover is a deterministic function of the item's id, so the same
item draws the same picture on every launch and the masonry is a stable grid
instead of noise. See `Components/GeneratedArt.swift`.

**Live AI depends on the gateway having capacity.** At the time of writing,
`1pkapi.com` returns `"All available accounts exhausted"` for every model on
this key. That is handled, not hidden: the API maps it to a structured
`AI_UNAVAILABLE`, and the app shows a "tutor is offline" state and stays fully
usable. Ask, quizzes, translation and thread summaries all start working the
moment the account has capacity — nothing else needs to change.

## iOS build notes

All three of these are scars.

**`xcodegen` is required.** The project uses explicit file references, so a new
`.swift` file does not exist to the build until the project is regenerated.
Change signing, bundle id or Info.plist keys in `apps/mobile/project.yml`, not
in Xcode — the next `generate` overwrites anything set in the IDE.

**`DerivedData` must stay outside the repo.** This checkout lives under an
iCloud-synced `Documents`; the sync daemon puts `com.apple.FinderInfo` and
`com.apple.fileprovider.*` extended attributes on build products, and codesign
refuses them: `resource fork, Finder information, or similar detritus not
allowed`. `scripts/dev.sh ios` points `-derivedDataPath` at `/tmp`.

**The simulator build is ad-hoc signed, not unsigned.** An unsigned app has no
entitlements at all, so it has no keychain access group and every `SecItemAdd`
fails with `errSecMissingEntitlement`. That showed up as the app asking you to
sign in again on every launch, with nothing anywhere saying why. Ad-hoc (`"-"`)
needs no team and no provisioning profile, so a machine that has never seen
this project's signing can still build and run it. Device builds still need a
Team ID in `apps/mobile/Configs/Local.xcconfig` (gitignored).

## Demo launch arguments

`simctl` can launch and screenshot but cannot tap, so every screen is reachable
by argument. Without this, anything three taps deep is a screen nobody has
actually looked at.

```bash
xcrun simctl launch <UDID> luke.novi.app \
  -demoResetSession YES                        # forget stored tokens → sign-in
  -demoEmail a@example.com -demoPassword ...   # sign in on launch, for real
  -demoSkipIntro YES                           # straight past the opening
  -demoHoldIntro YES                           # stop on the opening's last frame
  -demoTab home|explore|ask|passport|profile
  -demoQuestion "why does a derivative represent slope"
  -demoSearch photosynthesis
  -apiBaseURL http://host:8000/v1
```

`-demoEmail` signs in against the real API rather than faking a signed-in
state. A screenshot of a state the server cannot produce is not evidence of
anything.

## Where the decisions are written down

Backend and schema: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md),
[`docs/DATABASE.md`](docs/DATABASE.md). HTTP contract:
[`docs/API.md`](docs/API.md). Client-side reasoning lives next to the code it
explains — start at [`Design/NV.swift`](apps/mobile/Novi/Design/NV.swift),
[`Components/Waterfall.swift`](apps/mobile/Novi/Components/Waterfall.swift) and
[`Core/APIClient.swift`](apps/mobile/Novi/Core/APIClient.swift).

## What is not built

No streaming responses, no real ingestion pipeline, no admin dashboard, and no
client-side test target — the backend has 39 tests, the app has none. Projects
exist in the API and the schema but have no screen yet. Dark mode is not
implemented; the app is light-only and says so rather than shipping a second
palette nobody has checked.
