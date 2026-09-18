"""Reading content out of the store, with the caller's own state attached."""

from __future__ import annotations

import re
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.core.lang import content_matches_language, language_clause
from novi.models import (
    Concept,
    Content,
    ContentConcept,
    ContentLike,
    SavedContent,
)
from novi.schemas.content import ConceptRef, ContentOut


async def concept_refs(
    db: AsyncSession, content_ids: list[uuid.UUID]
) -> dict[uuid.UUID, list[ConceptRef]]:
    """Concepts for many items in one query.

    Done in bulk because the feed renders 20 cards and the per-card version of
    this is the classic N+1 that makes a feed take a second to load.
    """
    if not content_ids:
        return {}
    rows = (
        await db.execute(
            select(ContentConcept.content_id, Concept)
            .join(Concept, Concept.id == ContentConcept.concept_id)
            .where(ContentConcept.content_id.in_(content_ids))
            .order_by(ContentConcept.relevance.desc())
        )
    ).all()
    out: dict[uuid.UUID, list[ConceptRef]] = {}
    for content_id, concept in rows:
        out.setdefault(content_id, []).append(
            ConceptRef(id=concept.id, slug=concept.slug, name=concept.name)
        )
    return out


async def user_state(
    db: AsyncSession, user_id: uuid.UUID, content_ids: list[uuid.UUID]
) -> tuple[set[uuid.UUID], set[uuid.UUID]]:
    """(saved, liked) for these items — two queries, not two per card."""
    if not content_ids:
        return set(), set()
    saved = set(
        (
            await db.execute(
                select(SavedContent.content_id).where(
                    SavedContent.user_id == user_id, SavedContent.content_id.in_(content_ids)
                )
            )
        ).scalars()
    )
    liked = set(
        (
            await db.execute(
                select(ContentLike.content_id).where(
                    ContentLike.user_id == user_id, ContentLike.content_id.in_(content_ids)
                )
            )
        ).scalars()
    )
    return saved, liked


def to_out(content: Content, concepts: list[ConceptRef] | None = None) -> ContentOut:
    out = ContentOut.model_validate(content)
    out.concepts = concepts or []
    return out


def _in_language(stmt, language: str | None):
    if not language:
        return stmt
    return stmt.where(language_clause(Content.language, language))


def _keep_language(
    rows: list[Content], language: str | None, *, limit: int | None = None
) -> list[Content]:
    if not language:
        return rows[:limit] if limit is not None else rows
    kept = [
        row
        for row in rows
        if content_matches_language(row.language, row.title, row.description, language)
    ]
    return kept[:limit] if limit is not None else kept


async def related(
    db: AsyncSession,
    content: Content,
    *,
    limit: int = 8,
    language: str | None = None,
) -> list[Content]:
    """Other items covering the same concepts.

    Ranked by how many concepts they share, then by quality — a card that
    covers two of the same ideas is more related than one that covers one.
    """
    fetch = limit * 3 if language else limit
    concept_ids = (
        await db.execute(
            select(ContentConcept.concept_id).where(ContentConcept.content_id == content.id)
        )
    ).scalars().all()

    if concept_ids:
        overlap = func.count(ContentConcept.concept_id).label("overlap")
        stmt = (
            select(Content, overlap)
            .join(ContentConcept, ContentConcept.content_id == Content.id)
            .where(
                ContentConcept.concept_id.in_(concept_ids),
                Content.id != content.id,
            )
        )
        stmt = _in_language(stmt, language)
        rows = (
            await db.execute(
                stmt.group_by(Content.id)
                .order_by(overlap.desc(), Content.quality.desc())
                .limit(fetch)
            )
        ).all()
        related_rows = _keep_language([r[0] for r in rows], language, limit=limit)
        if related_rows:
            return related_rows

    # Nothing tagged yet: fall back to the same subject.
    fallback_stmt = select(Content).where(
        Content.subject_id == content.subject_id, Content.id != content.id
    )
    fallback_stmt = _in_language(fallback_stmt, language)
    fallback = list(
        (
            await db.execute(
                fallback_stmt.order_by(Content.quality.desc()).limit(fetch)
            )
        ).scalars()
    )
    return _keep_language(fallback, language, limit=limit)


async def search(
    db: AsyncSession,
    *,
    query: str,
    limit: int = 20,
    media_kind: str | None = None,
    language: str | None = None,
) -> list[Content]:
    """Full-text search, widening from precision to recall.

    Three passes, because one is never enough:

    1. All terms (`websearch_to_tsquery` ANDs them). Best results when it hits.
    2. Any term, ranked by `ts_rank`. Needed because the index is built with
       the `simple` configuration, which does not strip stopwords — so "how do
       derivatives work" ANDs four words, two of which appear in nothing, and
       returns an empty page for a perfectly good query.
    3. Substring match on the individual words, for a query the parser and the
       stemmer both miss.

    `simple` rather than `english` is deliberate: Chinese tokens must stay
    searchable for zh profiles, and the English stemmer would mangle them.
    Language filtering happens after retrieval so a mis-tagged card cannot
    leak into an English-only feed.
    """
    cleaned = query.strip()
    if not cleaned:
        return []

    words = [w for w in re.split(r"\W+", cleaned) if len(w) > 1]
    fetch = limit * 3 if language else limit

    async def by_tsquery(expression: str) -> list[Content]:
        tsquery = func.websearch_to_tsquery("simple", expression)
        stmt = (
            select(Content)
            .where(Content.search_vector.op("@@")(tsquery))
            .order_by(func.ts_rank(Content.search_vector, tsquery).desc(), Content.quality.desc())
            .limit(fetch)
        )
        if media_kind:
            stmt = stmt.where(Content.media_kind == media_kind)
        stmt = _in_language(stmt, language)
        rows = list((await db.execute(stmt)).scalars())
        return _keep_language(rows, language, limit=limit)

    if rows := await by_tsquery(cleaned):
        return rows

    if len(words) > 1 and (rows := await by_tsquery(" OR ".join(words))):
        return rows

    if not words:
        return []
    stmt = (
        select(Content)
        .where(
            or_(
                *[Content.title.ilike(f"%{w}%") for w in words],
                *[Content.topic.ilike(f"%{w}%") for w in words],
            )
        )
        .order_by(Content.quality.desc())
        .limit(fetch)
    )
    if media_kind:
        stmt = stmt.where(Content.media_kind == media_kind)
    stmt = _in_language(stmt, language)
    return _keep_language(list((await db.execute(stmt)).scalars()), language, limit=limit)
