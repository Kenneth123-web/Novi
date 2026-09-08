"""Idempotent seeder.

    .venv/bin/python -m database.seeds.seed

Idempotent because it runs repeatedly during development, and a seeder that
duplicates its own rows makes every unique constraint in the schema look like a
bug. Everything upserts on its natural key.
"""

from __future__ import annotations

import asyncio
import sys

from novi.db import dispose_engine, get_sessionmaker
from novi.models import (
    Concept,
    ConceptEdge,
    Content,
    ContentConcept,
    Discussion,
    DiscussionComment,
    Subject,
)
from sqlalchemy import select

from database.seeds.catalog import CONCEPTS, EDGES, SUBJECTS
from database.seeds.content import build_discussions, build_for_concept

# Discussions only for concepts likely to be demoed; three threads for all 133
# concepts is 400 rows of near-identical text that nobody will ever open.
DISCUSSION_CONCEPTS = {
    "derivatives", "limits", "integrals", "chain-rule", "probability", "bayes-theorem",
    "photosynthesis", "cellular-respiration", "dna-replication", "natural-selection",
    "newtons-laws", "ohms-law", "entropy", "special-relativity",
    "big-o", "recursion", "neural-networks", "backpropagation", "dynamic-programming",
    "supply-demand", "inflation", "chemical-bonding", "equilibrium", "acids-bases",
    "cognitive-biases", "climate-change", "close-reading",
}


async def seed() -> dict[str, int]:
    async with get_sessionmaker()() as db:
        # ── Subjects ─────────────────────────────────────────────────────────
        subjects = {s.slug: s for s in (await db.execute(select(Subject))).scalars()}
        for order, spec in enumerate(SUBJECTS):
            row = subjects.get(spec["slug"])
            if row is None:
                row = Subject(slug=spec["slug"])
                db.add(row)
                subjects[spec["slug"]] = row
            row.name = spec["name"]
            row.description = spec["description"]
            row.icon = spec["icon"]
            row.accent = spec["accent"]
            row.sort_order = order
        await db.flush()

        # ── Concepts ─────────────────────────────────────────────────────────
        concepts = {c.slug: c for c in (await db.execute(select(Concept))).scalars()}
        concept_subject: dict[str, str] = {}
        for subject_slug, rows in CONCEPTS.items():
            subject = subjects[subject_slug]
            for order, (slug, name, difficulty) in enumerate(rows):
                row = concepts.get(slug)
                if row is None:
                    row = Concept(slug=slug)
                    db.add(row)
                    concepts[slug] = row
                row.name = name
                row.subject_id = subject.id
                row.difficulty = difficulty
                row.sort_order = order
                concept_subject[slug] = subject_slug
        await db.flush()

        # ── Edges ────────────────────────────────────────────────────────────
        existing_edges = {
            (e.from_id, e.to_id) for e in (await db.execute(select(ConceptEdge))).scalars()
        }
        edge_count = 0
        for from_slug, to_slug, kind in EDGES:
            a, b = concepts.get(from_slug), concepts.get(to_slug)
            if a is None or b is None:
                # A typo in the edge list would otherwise fail as an integrity
                # error 60 rows later, pointing at the wrong thing.
                print(f"  ! edge references unknown concept: {from_slug} -> {to_slug}")
                continue
            if (a.id, b.id) in existing_edges:
                continue
            db.add(ConceptEdge(from_id=a.id, to_id=b.id, kind=kind))
            edge_count += 1
        await db.flush()

        # ── Content ──────────────────────────────────────────────────────────
        existing_content = {
            (c.platform, c.external_id): c
            for c in (await db.execute(select(Content))).scalars()
        }
        linked = {
            (link.content_id, link.concept_id)
            for link in (await db.execute(select(ContentConcept))).scalars()
        }
        content_count = 0
        for slug, concept in concepts.items():
            subject_slug = concept_subject.get(slug)
            if subject_slug is None:
                continue
            for sample in build_for_concept(slug, concept.name, concept.difficulty):
                key = (sample.platform, sample.external_id)
                row = existing_content.get(key)
                if row is None:
                    row = Content(platform=sample.platform, external_id=sample.external_id)
                    db.add(row)
                    existing_content[key] = row
                    content_count += 1
                row.title = sample.title
                row.description = sample.description
                row.creator = sample.creator
                row.media_kind = sample.media_kind
                row.language = sample.language
                row.subject_id = subjects[subject_slug].id
                row.topic = sample.topic
                row.tags = sample.tags
                row.likes = sample.likes
                row.comments = sample.comments
                row.quality = sample.quality
                row.difficulty = sample.difficulty
                row.thumbnail_ratio = sample.thumbnail_ratio
                row.duration_seconds = sample.duration_seconds
                # Never unset. These rows are stand-ins and the client says so.
                row.is_sample = True
                await db.flush()
                if (row.id, concept.id) not in linked:
                    db.add(ContentConcept(content_id=row.id, concept_id=concept.id, relevance=1.0))
                    linked.add((row.id, concept.id))

        # ── Discussions ──────────────────────────────────────────────────────
        existing_disc = {
            d.external_id: d for d in (await db.execute(select(Discussion))).scalars()
        }
        # Which discussions already have comments, asked once. Touching
        # `row.comments_` on a row that was just added triggers a lazy load,
        # which is a MissingGreenlet under asyncpg.
        with_comments = set(
            (await db.execute(select(DiscussionComment.discussion_id).distinct())).scalars()
        )
        disc_count = 0
        for slug in DISCUSSION_CONCEPTS:
            concept = concepts.get(slug)
            if concept is None:
                continue
            for sample in build_discussions(slug, concept.name, concept_subject.get(slug, "")):
                row = existing_disc.get(sample.external_id)
                if row is None:
                    row = Discussion(external_id=sample.external_id)
                    db.add(row)
                    existing_disc[sample.external_id] = row
                    disc_count += 1
                row.platform = "reddit"
                row.community = sample.community
                row.title = sample.title
                row.body = sample.body
                row.author = sample.author
                row.language = "en"
                row.upvotes = sample.upvotes
                row.comment_count = len(sample.comments)
                row.concept_id = concept.id
                row.is_sample = True
                await db.flush()
                if row.id not in with_comments:
                    with_comments.add(row.id)
                    for i, body in enumerate(sample.comments):
                        db.add(
                            DiscussionComment(
                                discussion_id=row.id,
                                author=f"{sample.author[:6]}_{i}",
                                body=body,
                                upvotes=max(1, sample.upvotes // (i + 3)),
                                ordinal=i,
                            )
                        )

        await db.commit()
        return {
            "subjects": len(subjects),
            "concepts": len(concepts),
            "new_edges": edge_count,
            "new_content": content_count,
            "new_discussions": disc_count,
        }


async def main() -> int:
    stats = await seed()
    print("seeded: " + ", ".join(f"{v} {k}" for k, v in stats.items()))
    await dispose_engine()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
