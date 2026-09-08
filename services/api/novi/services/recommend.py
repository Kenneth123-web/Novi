"""Ranking the feed.

Deterministic weighted scoring, not a learned model. That is a deliberate
starting point: every number below can be explained to a person, the reason
string shown on a card is computed from the same components that produced the
rank, and an A/B test against something smarter needs a baseline to beat.

The term that matters most is `gap`. A recommender built only from interest
converges on showing the learner what they already know, which feels great for
a week and teaches nothing. `gap` is what pushes the feed one step ahead.
"""

from __future__ import annotations

import math
import uuid
from dataclasses import dataclass, field
from datetime import UTC, datetime

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.models import (
    MASTERY_RANK,
    Concept,
    Content,
    ContentConcept,
    Interaction,
    LearningProgress,
    Profile,
    Subject,
)

WEIGHTS = {
    "interest": 0.30,
    "gap": 0.25,
    "quality": 0.15,
    "recent": 0.15,
    "format": 0.10,
    "fresh": 0.05,
}

# Content whose only concepts are already "mastered" is not worth the slot.
MASTERED = MASTERY_RANK["mastered"]

# Which content formats each stated learning preference likes.
PREFERENCE_FORMATS = {
    "short_video": {"video"},
    "long_explanation": {"video", "article"},
    "visual": {"image", "video"},
    "real_world": {"post", "article"},
    "tutorials": {"video", "article"},
    "projects": {"post", "article"},
    "discussions": {"discussion", "post"},
    "news": {"post"},
    "case_studies": {"article", "post"},
    "practice": {"article"},
}


@dataclass
class Scored:
    content: Content
    score: float
    components: dict[str, float] = field(default_factory=dict)
    reason: str = ""


def _gap_score(mastery_ranks: list[int], difficulty: int, stage_level: int) -> float:
    """How much there is to learn here.

    Peaks for content one step beyond where the learner is, and falls off both
    for what they have mastered and for what is far over their head. A learner
    on limits should be shown derivatives, not measure theory.
    """
    if not mastery_ranks:
        # Nothing known about it at all — genuinely new, worth a look.
        return 0.7
    best = max(mastery_ranks)
    if best >= MASTERED:
        return 0.05
    freshness = 1.0 - (best / MASTERED)
    stretch = difficulty - stage_level
    # A bell around "one level up".
    reach = math.exp(-((stretch - 1) ** 2) / 2.0)
    return max(0.0, min(1.0, 0.6 * freshness + 0.4 * reach))


def _recency_score(seconds_since: float | None) -> float:
    """Exponential decay with a one-week half life."""
    if seconds_since is None:
        return 0.0
    half_life = 7 * 24 * 3600
    return math.exp(-seconds_since * math.log(2) / half_life)


STAGE_LEVEL = {"middle": 1, "high": 2, "college": 3, "other": 2}


async def rank_feed(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    limit: int = 20,
    offset: int = 0,
    subject_slug: str | None = None,
    pool: int = 300,
) -> list[Scored]:
    """Candidate generation, scoring, diversity, then the page."""
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user_id))
    ).scalar_one_or_none()
    interests: dict[str, float] = dict(profile.subject_interests) if profile else {}
    preferences = set(profile.learning_preferences) if profile else set()
    stage_level = STAGE_LEVEL.get((profile.stage if profile else None) or "other", 2)

    preferred_formats: set[str] = set()
    for pref in preferences:
        preferred_formats |= PREFERENCE_FORMATS.get(pref, set())

    subjects = {s.id: s.slug for s in (await db.execute(select(Subject))).scalars()}

    # ── Candidates ───────────────────────────────────────────────────────────
    # Everything the learner has already seen is excluded here rather than
    # filtered after scoring: paging over a list that still contains seen items
    # makes page 2 shorter than page 1 for no visible reason.
    seen = set(
        (
            await db.execute(
                select(Interaction.content_id).where(
                    Interaction.user_id == user_id,
                    Interaction.content_id.is_not(None),
                    Interaction.kind.in_(("VIEW", "SKIP")),
                )
            )
        ).scalars()
    )

    stmt = select(Content).limit(pool)
    if subject_slug:
        stmt = stmt.join(Subject, Content.subject_id == Subject.id).where(
            Subject.slug == subject_slug
        )
    elif interests:
        # Only bother with subjects the learner has any interest in at all.
        wanted = [sid for sid, slug in subjects.items() if interests.get(slug, 0) > 0.05]
        if wanted:
            stmt = stmt.where(Content.subject_id.in_(wanted))
    stmt = stmt.order_by(Content.quality.desc())

    candidates = [c for c in (await db.execute(stmt)).scalars() if c.id not in seen]
    if not candidates:
        return []

    # ── Signals ──────────────────────────────────────────────────────────────
    concept_rows = (
        await db.execute(
            select(ContentConcept.content_id, ContentConcept.concept_id, Concept.difficulty)
            .join(Concept, Concept.id == ContentConcept.concept_id)
            .where(ContentConcept.content_id.in_([c.id for c in candidates]))
        )
    ).all()
    by_content: dict[uuid.UUID, list[tuple[uuid.UUID, int]]] = {}
    for content_id, concept_id, difficulty in concept_rows:
        by_content.setdefault(content_id, []).append((concept_id, difficulty))

    progress = {
        row.concept_id: MASTERY_RANK[row.mastery]
        for row in (
            await db.execute(
                select(LearningProgress).where(LearningProgress.user_id == user_id)
            )
        ).scalars()
    }

    # Most recent touch per subject, for the "recent behaviour" term.
    recent_rows = (
        await db.execute(
            select(Concept.subject_id, func.max(Interaction.occurred_at))
            .join(Concept, Concept.id == Interaction.concept_id)
            .where(Interaction.user_id == user_id)
            .group_by(Concept.subject_id)
        )
    ).all()
    now = datetime.now(UTC)
    recent_by_subject = {
        sid: (now - ts).total_seconds() for sid, ts in recent_rows if ts is not None
    }

    # ── Score ────────────────────────────────────────────────────────────────
    scored: list[Scored] = []
    for content in candidates:
        slug = subjects.get(content.subject_id, "")
        links = by_content.get(content.id, [])
        difficulty = content.difficulty or 2

        interest = interests.get(slug, 0.1)
        known = [progress[cid] for cid, _ in links if cid in progress]
        gap = _gap_score(known, difficulty, stage_level)
        quality = content.quality
        recent = _recency_score(recent_by_subject.get(content.subject_id))
        fmt = 1.0 if (not preferred_formats or content.media_kind in preferred_formats) else 0.35
        fresh = _recency_score(
            (now - content.published_at).total_seconds() if content.published_at else None
        )

        components = {
            "interest": interest,
            "gap": gap,
            "quality": quality,
            "recent": recent,
            "format": fmt,
            "fresh": fresh,
        }
        total = sum(WEIGHTS[k] * v for k, v in components.items())
        scored.append(
            Scored(
                content=content,
                score=total,
                components=components,
                reason=_reason(components, slug),
            )
        )

    scored.sort(key=lambda s: s.score, reverse=True)
    return _diversify(scored)[offset : offset + limit]


def _reason(components: dict[str, float], subject_slug: str) -> str:
    """The line under "Why this?" on the detail page.

    Generated from the components that actually produced the rank, so it can
    never drift from the ranking the way a hand-written string would.
    """
    top = max(components, key=lambda k: WEIGHTS[k] * components[k])
    pretty = subject_slug.replace("-", " ") or "your subjects"
    return {
        "interest": f"You follow {pretty}",
        "gap": "A step beyond what you have covered",
        "quality": "One of the best explanations we have on this",
        "recent": f"You have been working on {pretty}",
        "format": "Matches the formats you prefer",
        "fresh": "Recently published",
    }[top]


def _diversify(scored: list[Scored], *, max_per_creator: int = 2, window: int = 6) -> list[Scored]:
    """Stop one creator or one topic from owning the screen.

    Applied over a sliding window rather than the whole list: the constraint
    that matters is what the learner can see at once, and a global cap would
    push a genuinely relevant third item to position 200.
    """
    out: list[Scored] = []
    for item in scored:
        recent = out[-window:]
        creator_count = sum(1 for s in recent if s.content.creator == item.content.creator)
        topic_count = sum(1 for s in recent if s.content.topic == item.content.topic)
        if creator_count >= max_per_creator or topic_count >= 3:
            continue
        out.append(item)
    return out
