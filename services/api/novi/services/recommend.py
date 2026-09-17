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

from novi.areas import area_for_concept, area_name, concepts_for_areas
from novi.core.lang import content_matches_language, language_clause, language_key
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
    "interest": 0.18,
    "gap": 0.16,
    "area": 0.22,
    "struggle": 0.12,
    "quality": 0.12,
    "recent": 0.10,
    "format": 0.07,
    "fresh": 0.03,
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
    area_key: str = ""


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
GRADE_LEVEL = {
    "6": 1,
    "7": 1,
    "8": 1,
    "9": 2,
    "10": 2,
    "11": 2,
    "12": 3,
    "freshman": 3,
    "sophomore": 3,
    "junior": 4,
    "senior": 4,
    "grad": 5,
    "adult": 3,
    "self-taught": 2,
}


def _learner_level(profile: Profile | None) -> int:
    if profile is None:
        return 2
    if profile.grade and profile.grade in GRADE_LEVEL:
        return GRADE_LEVEL[profile.grade]
    return STAGE_LEVEL.get(profile.stage or "other", 2)


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
    weak = set(profile.weak_subjects) if profile else set()
    focus_areas: dict[str, list[str]] = dict(profile.focus_areas) if profile else {}
    selected_concepts = {
        subject: concepts_for_areas(subject, areas)
        for subject, areas in focus_areas.items()
        if areas
    }
    stage_level = _learner_level(profile)
    pref_lang = language_key(profile.language if profile else None) or "en"

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

    stmt = select(Content).where(language_clause(Content.language, pref_lang)).limit(pool)
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

    candidates = [
        content
        for content in (await db.execute(stmt)).scalars()
        if content.id not in seen
        and content_matches_language(
            content.language, content.title, content.description, pref_lang
        )
    ]
    if not candidates:
        return []

    # ── Signals ──────────────────────────────────────────────────────────────
    concept_rows = (
        await db.execute(
            select(
                ContentConcept.content_id,
                ContentConcept.concept_id,
                Concept.difficulty,
                Concept.slug,
            )
            .join(Concept, Concept.id == ContentConcept.concept_id)
            .where(ContentConcept.content_id.in_([c.id for c in candidates]))
        )
    ).all()
    by_content: dict[uuid.UUID, list[tuple[uuid.UUID, int, str]]] = {}
    for content_id, concept_id, difficulty, concept_slug in concept_rows:
        by_content.setdefault(content_id, []).append((concept_id, difficulty, concept_slug))

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
        concept_slugs = [slug for _, _, slug in links]

        interest = interests.get(slug, 0.1)
        known = [progress[cid] for cid, _, _ in links if cid in progress]
        gap = _gap_score(known, difficulty, stage_level)
        area, area_slug = _area_score(slug, concept_slugs, selected_concepts)
        # Real ingested tutorials outrank generated stand-ins when both exist.
        quality = min(1.0, content.quality + (0.0 if content.is_sample else 0.08))
        recent = _recency_score(recent_by_subject.get(content.subject_id))
        fmt = 1.0 if (not preferred_formats or content.media_kind in preferred_formats) else 0.35
        fresh = _recency_score(
            (now - content.published_at).total_seconds() if content.published_at else None
        )
        struggle = 1.0 if slug in weak else 0.12

        components = {
            "interest": interest,
            "gap": gap,
            "area": area,
            "struggle": struggle,
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
                reason=_reason(components, slug, area_slug),
                area_key=f"{slug}:{area_slug}" if area_slug else slug,
            )
        )

    scored.sort(key=lambda s: s.score, reverse=True)
    return _diversify(scored)[offset : offset + limit]


def _area_score(
    subject_slug: str,
    concept_slugs: list[str],
    selected_concepts: dict[str, set[str]],
) -> tuple[float, str | None]:
    """How well this card matches the part of the subject the learner named.

    Unspecified areas mean the whole subject (legacy profiles). A miss inside
    a named subject is still the right class, just the wrong chapter, so it
    is not zeroed — it is pushed behind the chapters they actually picked.
    """
    wanted = selected_concepts.get(subject_slug)
    if not wanted:
        return 0.55, area_for_concept(subject_slug, concept_slugs[0]) if concept_slugs else None
    for slug in concept_slugs:
        if slug in wanted:
            return 1.0, area_for_concept(subject_slug, slug)
    return 0.12, area_for_concept(subject_slug, concept_slugs[0]) if concept_slugs else None


def _reason(components: dict[str, float], subject_slug: str, area_slug: str | None) -> str:
    """The line under "Why this?" on the detail page.

    Generated from the components that actually produced the rank, so it can
    never drift from the ranking the way a hand-written string would.
    """
    top = max(components, key=lambda k: WEIGHTS[k] * components[k])
    pretty = subject_slug.replace("-", " ") or "your subjects"
    area_label = area_name(subject_slug, area_slug) if area_slug else ""
    return {
        "interest": f"You follow {pretty}",
        "gap": "A step beyond what you have covered",
        "area": (
            f"The {area_label.lower()} part of {pretty} you asked for"
            if area_label
            else f"A part of {pretty} you asked for"
        ),
        "struggle": f"You said {pretty} is the hard one",
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
