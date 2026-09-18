"""The Ask flow: explain, then open the rabbit hole.

The plan's central idea is that the page does not end when the explanation
does. So this returns the explanation *and* the content to explore next, in
one response — a second round trip would put a spinner exactly where the
learner's momentum is.
"""

from __future__ import annotations

import re
import uuid

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.ai.gateway import gateway
from novi.ai.prompts import explain as explain_prompt
from novi.core.errors import NotFound
from novi.core.logging import get_logger
from novi.models import (
    AIResponse,
    Concept,
    ConceptEdge,
    Content,
    ContentConcept,
    Discussion,
    LearningProgress,
    Profile,
    Question,
    Subject,
    User,
)
from novi.schemas.ai import Explanation
from novi.services import content_service, knowledge

logger = get_logger(__name__)



async def _catalog_names(db: AsyncSession, subject_slugs: list[str], limit: int = 40) -> list[str]:
    """Concept names the app can open, biased to what the learner studies.

    Passed to the model so `related_concepts` comes back as things that
    actually resolve to a page. Capped, because the whole catalog is 133 names
    and most of them are irrelevant to any one question.
    """
    stmt = select(Concept.name).order_by(Concept.sort_order).limit(limit)
    if subject_slugs:
        stmt = (
            select(Concept.name)
            .join(Subject, Subject.id == Concept.subject_id)
            .where(Subject.slug.in_(subject_slugs))
            .order_by(Concept.sort_order)
            .limit(limit)
        )
    return list((await db.execute(stmt)).scalars().all())


async def _known_concepts(db: AsyncSession, user_id: uuid.UUID, limit: int = 8) -> list[str]:
    rows = (
        await db.execute(
            select(Concept.name)
            .join(LearningProgress, LearningProgress.concept_id == Concept.id)
            .where(LearningProgress.user_id == user_id)
            .order_by(LearningProgress.last_touched_at.desc())
            .limit(40)
        )
    ).scalars().all()
    return rows[:limit]


async def ask(
    db: AsyncSession,
    *,
    user: User,
    question: str,
    mode: str = "explain",
    content_id: uuid.UUID | None = None,
    concept_id: uuid.UUID | None = None,
) -> tuple[Question, Explanation, dict]:
    """Returns (question row, parsed explanation, discovery rail)."""
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user.id))
    ).scalar_one_or_none()

    content = await db.get(Content, content_id) if content_id else None
    if content_id and content is None:
        raise NotFound("Content not found")
    if concept_id and await db.get(Concept, concept_id) is None:
        raise NotFound("Concept not found")
    subjects = list(profile.subject_order) if profile else []

    known = await _known_concepts(db, user.id)
    catalog = await _catalog_names(db, subjects)
    user_prompt = explain_prompt.build_user_prompt(
        question=question,
        stage=profile.stage if profile else None,
        grade=profile.grade if profile else None,
        curriculum=profile.curriculum if profile else None,
        subjects=subjects,
        weak_subjects=list(profile.weak_subjects) if profile else None,
        mode=mode,
        known_concepts=known,
        content_title=content.title if content else None,
        catalog=catalog,
    )

    # Raises AIUnavailable, which the router turns into a 503 the client shows
    # as a "tutor unavailable" state rather than a broken page.
    result = await gateway.complete_json(
        system=explain_prompt.SYSTEM,
        user=user_prompt,
        required_keys=explain_prompt.REQUIRED_KEYS,
    )

    explanation = Explanation.model_validate(
        {k: v for k, v in result.data.items() if k in Explanation.model_fields}
    )

    row = Question(
        user_id=user.id,
        text_=question,
        mode=mode,
        content_id=content_id,
        concept_id=concept_id,
    )
    db.add(row)
    await db.flush()
    db.add(
        AIResponse(
            question_id=row.id,
            payload=result.data,
            model=result.model,
            prompt_version=explain_prompt.VERSION,
            input_tokens=result.input_tokens,
            output_tokens=result.output_tokens,
            latency_ms=result.latency_ms,
        )
    )

    await knowledge.record_interaction(
        db,
        user_id=user.id,
        kind="ASK",
        content_id=content_id,
        concept_id=concept_id,
        context={"mode": mode},
    )

    rail = await build_discovery_rail(
        db,
        queries=explanation.search_queries or [explanation.concept or question],
        related_names=explanation.related_concepts,
        exclude_content_id=content_id,
    )
    return row, explanation, rail


async def build_discovery_rail(
    db: AsyncSession,
    *,
    queries: list[str],
    related_names: list[str],
    exclude_content_id: uuid.UUID | None = None,
    per_bucket: int = 6,
) -> dict:
    """Turn the model's own search terms into things to watch, read and discuss.

    The model generates the queries; the retrieval is ours. Asking a model to
    *name* content would produce plausible titles that do not exist — running
    its queries against our own store produces rows that do.

    Each query is run separately through `content_service.search`, which
    already widens from all-terms to any-term to substring. Joining them into
    one tsquery instead is what made this return nothing: "derivatives slope"
    ANDs two words, and no title contains both.
    """
    terms = [q.strip() for q in (queries or []) if q and q.strip()][:5]
    if not terms:
        return {"watch": [], "read": [], "discuss": [], "related_concepts": []}

    async def collect(media_kinds: tuple[str, ...]) -> list[Content]:
        # Ordered dict rather than a set: the first query is the model's best
        # guess at what the learner wants, and its results should lead.
        found: dict[uuid.UUID, Content] = {}
        for term in terms:
            for kind in media_kinds:
                for row in await content_service.search(
                    db, query=term, limit=per_bucket, media_kind=kind
                ):
                    if row.id != exclude_content_id and row.id not in found:
                        found[row.id] = row
            if len(found) >= per_bucket:
                break
        return list(found.values())[:per_bucket]

    watch = await collect(("video",))
    read = await collect(("article", "post", "image"))

    # Discussions are short and few, so a per-word substring match is both
    # cheap and more forgiving than full-text over a three-sentence body.
    words = {w for term in terms for w in re.split(r"\W+", term) if len(w) > 3}
    discuss: list[Discussion] = []
    if words:
        discuss = list(
            (
                await db.execute(
                    select(Discussion)
                    .where(
                        or_(
                            *[Discussion.title.ilike(f"%{w}%") for w in words],
                            *[Discussion.body.ilike(f"%{w}%") for w in words],
                        )
                    )
                    .order_by(Discussion.upvotes.desc())
                    .limit(4)
                )
            ).scalars()
        )

    related = await resolve_concepts(db, related_names)
    return {"watch": watch, "read": read, "discuss": discuss, "related_concepts": related}


async def resolve_concepts(db: AsyncSession, names: list[str]) -> list[dict]:
    """Match the model's related-concept names to rows in our graph.

    Names that match nothing are still returned, without an id. They are a real
    part of the answer, and dropping them would silently shorten the list the
    learner was shown; the client renders them as plain, non-tappable chips.
    """
    if not names:
        return []
    cleaned = [n.strip() for n in names if n and n.strip()][:8]
    if not cleaned:
        return []

    rows = (
        await db.execute(
            select(Concept).where(
                or_(*[Concept.name.ilike(n) for n in cleaned])
            )
        )
    ).scalars().all()
    by_lower = {c.name.lower(): c for c in rows}

    out: list[dict] = []
    for name in cleaned:
        match = by_lower.get(name.lower())
        out.append(
            {
                "name": name,
                "id": str(match.id) if match else None,
                "slug": match.slug if match else None,
            }
        )
    return out


async def concept_neighbours(db: AsyncSession, concept_id: uuid.UUID) -> list[Concept]:
    """The outgoing edges of a concept, for the "where next" strip."""
    concept = await db.get(Concept, concept_id)
    if concept is None:
        raise NotFound("Concept not found")
    ids = (
        await db.execute(
            select(ConceptEdge.to_id)
            .where(ConceptEdge.from_id == concept_id)
            .order_by(ConceptEdge.weight.desc())
            .limit(8)
        )
    ).scalars().all()
    if not ids:
        # Fall back to siblings in the same subject at a similar level, so the
        # strip is never empty for a concept nobody has drawn edges for yet.
        return list(
            (
                await db.execute(
                    select(Concept)
                    .where(Concept.subject_id == concept.subject_id, Concept.id != concept_id)
                    .order_by(func.abs(Concept.difficulty - concept.difficulty))
                    .limit(6)
                )
            ).scalars()
        )
    return list((await db.execute(select(Concept).where(Concept.id.in_(ids)))).scalars())


async def concepts_for_content(db: AsyncSession, content_id: uuid.UUID) -> list[Concept]:
    ids = (
        await db.execute(
            select(ContentConcept.concept_id).where(ContentConcept.content_id == content_id)
        )
    ).scalars().all()
    if not ids:
        return []
    return list((await db.execute(select(Concept).where(Concept.id.in_(ids)))).scalars())


async def subject_of(db: AsyncSession, concept: Concept) -> Subject | None:
    return await db.get(Subject, concept.subject_id)

