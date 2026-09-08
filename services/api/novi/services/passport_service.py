"""The Learning Passport: what the learner has actually done."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.models import (
    MASTERY_RANK,
    Concept,
    Interaction,
    LearningProgress,
    PassportStamp,
    Project,
    Quiz,
    Subject,
)

# What counts as "covered" in the headline number. `discovered` does not: the
# passport is a record of learning, and a card scrolled past is not learning.
COVERED_FROM = MASTERY_RANK["explored"]


async def overview(db: AsyncSession, user_id: uuid.UUID) -> dict:
    progress = (
        await db.execute(
            select(LearningProgress).where(LearningProgress.user_id == user_id)
        )
    ).scalars().all()

    concept_ids = [p.concept_id for p in progress]
    concepts = (
        (await db.execute(select(Concept).where(Concept.id.in_(concept_ids)))).scalars().all()
        if concept_ids
        else []
    )
    by_id = {c.id: c for c in concepts}
    subjects = {s.id: s for s in (await db.execute(select(Subject))).scalars()}

    covered = [p for p in progress if MASTERY_RANK[p.mastery] >= COVERED_FROM]
    subject_buckets: dict[uuid.UUID, list] = {}
    for p in progress:
        concept = by_id.get(p.concept_id)
        if concept is None:
            continue
        subject_buckets.setdefault(concept.subject_id, []).append((concept, p))

    sessions = (
        await db.execute(
            select(func.count(func.distinct(func.date(Interaction.occurred_at)))).where(
                Interaction.user_id == user_id
            )
        )
    ).scalar() or 0

    projects = (
        await db.execute(select(Project).where(Project.user_id == user_id))
    ).scalars().all()

    stamps = (
        await db.execute(
            select(PassportStamp)
            .where(PassportStamp.user_id == user_id)
            .order_by(PassportStamp.earned_at.desc())
        )
    ).scalars().all()

    subject_cards = []
    for subject_id, rows in subject_buckets.items():
        subject = subjects.get(subject_id)
        if subject is None:
            continue
        rows.sort(key=lambda pair: pair[0].sort_order)
        learned = sum(1 for _, p in rows if MASTERY_RANK[p.mastery] >= MASTERY_RANK["learned"])
        subject_cards.append(
            {
                "subject_id": str(subject.id),
                "slug": subject.slug,
                "name": subject.name,
                "icon": subject.icon,
                "accent": subject.accent,
                "learned": learned,
                "total_touched": len(rows),
                # Progress against what they have *engaged with*, not against
                # the whole catalog: a bar that reads 2% because the subject
                # has 400 concepts tells the learner nothing about their work.
                "progress": (learned / len(rows)) if rows else 0.0,
                "concepts": [
                    {
                        "id": str(c.id),
                        "slug": c.slug,
                        "name": c.name,
                        "mastery": p.mastery,
                        "confidence": round(p.confidence, 2),
                    }
                    for c, p in rows[:12]
                ],
            }
        )
    subject_cards.sort(key=lambda s: s["learned"], reverse=True)

    return {
        "concepts_covered": len(covered),
        "concepts_learned": sum(
            1 for p in progress if MASTERY_RANK[p.mastery] >= MASTERY_RANK["learned"]
        ),
        "subjects": len(subject_buckets),
        "projects": len(projects),
        "sessions": int(sessions),
        "subject_cards": subject_cards,
        "stamps": [
            {
                "kind": s.kind,
                "key": s.key,
                "title": s.title,
                "subtitle": s.subtitle,
                "icon": s.icon,
                "earned_at": s.earned_at,
            }
            for s in stamps
        ],
    }


async def history(db: AsyncSession, user_id: uuid.UUID, *, days: int = 14) -> list[dict]:
    """Per-day activity counts, most recent first.

    Aggregated in Postgres rather than by pulling every interaction and
    counting in Python: a heavy user has thousands of rows and the client needs
    fourteen numbers.
    """
    since = datetime.now(UTC) - timedelta(days=days)
    day = func.date(Interaction.occurred_at).label("day")
    rows = (
        await db.execute(
            select(day, Interaction.kind, func.count())
            .where(Interaction.user_id == user_id, Interaction.occurred_at >= since)
            .group_by(day, Interaction.kind)
            .order_by(day.desc())
        )
    ).all()

    buckets: dict[object, dict[str, int]] = {}
    for d, kind, count in rows:
        buckets.setdefault(d, {})[kind] = count

    quizzes = (
        await db.execute(
            select(func.date(Quiz.created_at), func.count())
            .where(Quiz.user_id == user_id, Quiz.completed_at.is_not(None))
            .group_by(func.date(Quiz.created_at))
        )
    ).all()
    quiz_by_day = dict(quizzes)

    out = []
    for d, kinds in sorted(buckets.items(), reverse=True):
        out.append(
            {
                "date": d,
                "concepts": kinds.get("CONCEPT_OPEN", 0) + kinds.get("MARK_LEARNED", 0),
                "content": kinds.get("VIEW", 0),
                "questions": kinds.get("ASK", 0),
                "quizzes": quiz_by_day.get(d, 0),
            }
        )
    return out
