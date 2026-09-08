# Database

PostgreSQL 17. 22 tables.

```bash
./scripts/dev.sh migrate                                  # upgrade head
.venv/bin/alembic -c database/alembic.ini downgrade -1    # back one
.venv/bin/alembic -c database/alembic.ini revision --autogenerate -m "..."
.venv/bin/alembic -c database/alembic.ini check           # models vs schema
```

`database/migrations/env.py` reads `DATABASE_URL` through the API's own
`Settings`, not from `alembic.ini`. One source of truth means a migration
cannot be applied to a different database than the service is about to use.
`alembic check` runs as part of `./scripts/dev.sh check`, so a model changed
without a migration fails locally and in CI rather than at deploy.

## Tables

| Group | Tables |
|---|---|
| Accounts | `users`, `profiles`, `sessions` |
| Catalog | `subjects`, `concepts`, `concept_edges` |
| Content | `content`, `content_concepts`, `discussions`, `discussion_comments` |
| Behaviour | `interactions`, `saved_content`, `content_likes`, `learning_progress` |
| Tutor | `questions`, `ai_responses` |
| Learning | `quizzes`, `quiz_questions`, `quiz_results` |
| Passport | `passport_stamps`, `projects`, `project_concepts` |

## Decisions

**Concepts, not just subjects, are the unit.** The tutor explains a concept, a
quiz tests one, the passport stamps one, and "knowledge gap" is measured per
concept. Subjects are only a grouping.

**`concept_edges` is directed.** Derivatives lead to integrals, not the other
way round, so each pair is stored once with a `kind`. This is what makes the
"rabbit hole" navigable and what lets the recommender suggest an adjacent
concept rather than only what the learner already knows.

**`profiles.subject_interests` is JSONB, not a join table.** It is read on
every feed request and rewritten on every meaningful interaction; a table would
mean N rows read and written where one column does. It also stays legible
enough to debug by eye, which a packed embedding would not be.

**`subjects.slug` is the real key.** Profiles, deep links and the interest map
are all keyed by slug, so the catalog can be reseeded without orphaning
anything. Renaming a slug is a data migration.

**`content.search_vector` is a generated column.** Postgres computes it from
title, topic and description, weighted A/B/C. It cannot disagree with the row
it indexes, which an application-maintained tsvector eventually does.

**`interactions` is append-only.** Progress, interest weights and the passport
are all derivable from it. When one of them is wrong it can be rebuilt — but
only because the raw events were kept.

**`quiz_questions.correct_index` lives in the table, not in the response.**
Grading happens server-side and the client is never sent the key until it has
answered. Hiding the answer in the UI while shipping it in the payload is not
hiding it.

**`content.is_sample` is a column, not a README note.** The store is seeded
with generated stand-ins, and the flag is what keeps that a fact the client can
read and render. See the README for the rules the generator follows.

**Constraint naming is explicit** (`models/base.py`). Without a convention,
Postgres invents a different name on every database and `downgrade()` cannot
find the constraint to drop.

## Seeds

```bash
./scripts/dev.sh seed
```

14 subjects, 133 concepts, 69 graph edges, 532 content items, 81 discussions.
Idempotent — everything upserts on its natural key, because a seeder that
duplicates its own rows makes every unique constraint look like a bug.
