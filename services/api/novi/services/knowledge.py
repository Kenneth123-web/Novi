"""The knowledge model: what the learner knows, and how that changes.

This is the part of the product that makes the feed different tomorrow from
what it is today, so the rules are written down rather than scattered through
the routes that trigger them.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from novi.models import (
    MASTERY_RANK,
    Concept,
    Interaction,
    LearningProgress,
    PassportStamp,
    Profile,
    Subject,
)

# What each interaction is worth on the mastery ladder. A view is not learning;
# it is evidence of exposure. Only a quiz can push a concept past "practiced",
# because only a quiz produces evidence the learner can actually do something.
INTERACTION_MASTERY = {
    "CONCEPT_OPEN": "discovered",
    "VIEW": "viewed",
    "ASK": "explored",
    "LIKE": "viewed",
    "SAVE": "viewed",
    "QUIZ_START": "explored",
    "QUIZ_COMPLETE": "practiced",
    "MARK_LEARNED": "learned",
}

# Interest deltas, applied to the subject the concept belongs to.
INTEREST_DELTA = {
    "VIEW": 0.010,
    "LIKE": 0.030,
    "SAVE": 0.040,
    "ASK": 0.035,
    "QUIZ_COMPLETE": 0.050,
    "MARK_LEARNED": 0.040,
    "SKIP": -0.015,
}

# A quiz has to be genuinely good to count as mastery, not merely passed.
MASTERY_SCORE_THRESHOLD = 0.8


def _now() -> datetime:
    return datetime.now(UTC)


def promote(current: str, candidate: str) -> str:
    """Mastery only ever moves forward.

    Without this, a learner who masters derivatives and later scrolls past a
    derivatives video would be demoted to "viewed" by that scroll, and the
    recommender would start re-teaching them something they know.
    """
    return candidate if MASTERY_RANK[candidate] > MASTERY_RANK[current] else current


async def get_or_create_progress(
    db: AsyncSession, user_id: uuid.UUID, concept_id: uuid.UUID
) -> LearningProgress:
    await db.execute(
        insert(LearningProgress)
        .values(user_id=user_id, concept_id=concept_id)
        .on_conflict_do_nothing(index_elements=["user_id", "concept_id"])
    )
    return (
        await db.execute(
            select(LearningProgress)
            .where(
                LearningProgress.user_id == user_id,
                LearningProgress.concept_id == concept_id,
            )
            .with_for_update()
        )
    ).scalar_one()


async def record_interaction(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    kind: str,
    content_id: uuid.UUID | None = None,
    concept_id: uuid.UUID | None = None,
    dwell_seconds: int = 0,
    context: dict | None = None,
    concept_ids: list[uuid.UUID] | None = None,
) -> None:
    """Log the event, then let it move the knowledge and interest models.

    The event row is written unconditionally and first. Everything downstream
    is derived, so if a later step is wrong it can be recomputed — but only if
    the raw event was kept.
    """
    db.add(
        Interaction(
            user_id=user_id,
            kind=kind,
            content_id=content_id,
            concept_id=concept_id,
            dwell_seconds=max(0, dwell_seconds),
            context=context or {},
        )
    )

    targets = list(concept_ids or [])
    if concept_id and concept_id not in targets:
        targets.append(concept_id)
    if not targets:
        await db.flush()
        return

    concepts = (await db.execute(select(Concept).where(Concept.id.in_(targets)))).scalars().all()
    if not concepts:
        await db.flush()
        return

    mastery = INTERACTION_MASTERY.get(kind)
    for concept in concepts:
        progress = await get_or_create_progress(db, user_id, concept.id)
        if kind == "VIEW":
            progress.views += 1
        if mastery:
            progress.mastery = promote(progress.mastery, mastery)
        progress.last_touched_at = _now()

    delta = INTEREST_DELTA.get(kind, 0.0)
    if delta:
        await _nudge_interests(db, user_id, {c.subject_id for c in concepts}, delta)

    await db.flush()


async def _nudge_interests(
    db: AsyncSession, user_id: uuid.UUID, subject_ids: set[uuid.UUID], delta: float
) -> None:
    """Move the subject-interest weights that this interaction touched."""
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user_id))
    ).scalar_one_or_none()
    if profile is None:
        return

    slugs = (
        await db.execute(select(Subject.slug).where(Subject.id.in_(subject_ids)))
    ).scalars().all()
    if not slugs:
        return

    # Reassigned rather than mutated: SQLAlchemy does not see an in-place
    # change to a JSONB dict, and the write would be silently dropped.
    interests = dict(profile.subject_interests)
    for slug in slugs:
        # Clamped to [0, 1]. An unbounded counter becomes one runaway subject
        # that crowds everything else out of the feed.
        interests[slug] = max(0.0, min(1.0, interests.get(slug, 0.3) + delta))
    profile.subject_interests = interests


async def apply_quiz_result(
    db: AsyncSession, *, user_id: uuid.UUID, concept_id: uuid.UUID, score: float
) -> str:
    """Fold a quiz score into the concept's mastery. Returns the new state."""
    progress = await get_or_create_progress(db, user_id, concept_id)
    progress.quiz_attempts += 1
    progress.best_quiz_score = max(progress.best_quiz_score, score)
    progress.confidence = max(progress.confidence, score)
    progress.mastery = promote(progress.mastery, "practiced")
    if score >= MASTERY_SCORE_THRESHOLD:
        progress.mastery = promote(progress.mastery, "learned")
    progress.last_touched_at = _now()
    await db.flush()
    return progress.mastery


async def award_stamp(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    kind: str,
    key: str,
    title: str,
    subtitle: str = "",
    icon: str = "seal",
) -> PassportStamp | None:
    """Idempotent. Returns the stamp only when it was newly earned, so the
    caller knows whether to show the celebration."""
    stamp_id = (
        await db.execute(
            insert(PassportStamp)
            .values(
                user_id=user_id,
                kind=kind,
                key=key,
                title=title,
                subtitle=subtitle,
                icon=icon,
            )
            .on_conflict_do_nothing(index_elements=["user_id", "kind", "key"])
            .returning(PassportStamp.id)
        )
    ).scalar_one_or_none()
    if stamp_id is None:
        return None
    return await db.get(PassportStamp, stamp_id)
