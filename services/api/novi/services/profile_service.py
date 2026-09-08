"""Onboarding and profile updates."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.core.errors import ValidationFailed
from novi.models import Profile, Subject, User
from novi.schemas.profile import (
    CURRICULA,
    GOALS,
    LEARNING_PREFERENCES,
    STAGES,
    OnboardingRequest,
    ProfileUpdate,
)

# Interest weight a subject starts at when picked in onboarding, by rank.
# The first pick leads the feed, but not by so much that the fourth pick never
# appears — and none of them start at 1.0, so a subject the learner actually
# engages with can overtake one the questionnaire guessed at.
TOP_INTEREST = 0.85
MIN_INTEREST = 0.45


def _reject(field: str, values: list[str], allowed: list[str]) -> None:
    bad = [v for v in values if v not in allowed]
    if bad:
        raise ValidationFailed(
            f"Unknown {field}: {', '.join(bad)}",
            details={"field": field, "allowed": allowed},
        )


def _seed_interests(slugs: list[str]) -> dict[str, float]:
    if not slugs:
        return {}
    if len(slugs) == 1:
        return {slugs[0]: TOP_INTEREST}
    step = (TOP_INTEREST - MIN_INTEREST) / (len(slugs) - 1)
    return {slug: round(TOP_INTEREST - i * step, 3) for i, slug in enumerate(slugs)}


async def get_or_create(db: AsyncSession, user: User) -> Profile:
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user.id))
    ).scalar_one_or_none()
    if profile is None:
        profile = Profile(user_id=user.id)
        db.add(profile)
        await db.flush()
    return profile


async def _validate_subjects(db: AsyncSession, slugs: list[str]) -> None:
    known = {
        s.slug for s in (await db.execute(select(Subject).where(Subject.slug.in_(slugs)))).scalars()
    }
    unknown = [s for s in slugs if s not in known]
    if unknown:
        raise ValidationFailed(
            f"Unknown subjects: {', '.join(unknown)}",
            details={"field": "subject_slugs", "unknown": unknown},
        )


async def apply_onboarding(
    db: AsyncSession, user: User, body: OnboardingRequest
) -> Profile:
    if body.stage not in STAGES:
        raise ValidationFailed("Unknown stage", details={"field": "stage", "allowed": STAGES})
    if body.curriculum and body.curriculum not in CURRICULA:
        raise ValidationFailed(
            "Unknown curriculum", details={"field": "curriculum", "allowed": CURRICULA}
        )
    _reject("learning_preferences", body.learning_preferences, LEARNING_PREFERENCES)
    _reject("goals", body.goals, GOALS)

    # Duplicates would distort the interest weights, so they are dropped while
    # the caller's ordering is preserved.
    slugs = list(dict.fromkeys(body.subject_slugs))
    await _validate_subjects(db, slugs)

    profile = await get_or_create(db, user)
    profile.stage = body.stage
    profile.grade = body.grade
    profile.curriculum = body.curriculum
    profile.subject_order = slugs
    profile.subject_interests = _seed_interests(slugs)
    profile.learning_preferences = list(body.learning_preferences)
    profile.goals = list(body.goals)
    profile.language = body.language
    profile.interests_decayed_at = datetime.now(UTC)

    user.onboarded_at = datetime.now(UTC)
    await db.flush()
    return profile


async def update(db: AsyncSession, user: User, body: ProfileUpdate) -> Profile:
    profile = await get_or_create(db, user)

    if body.stage is not None:
        if body.stage not in STAGES:
            raise ValidationFailed("Unknown stage", details={"field": "stage", "allowed": STAGES})
        profile.stage = body.stage
    if body.curriculum is not None:
        if body.curriculum not in CURRICULA:
            raise ValidationFailed(
                "Unknown curriculum", details={"field": "curriculum", "allowed": CURRICULA}
            )
        profile.curriculum = body.curriculum
    if body.learning_preferences is not None:
        _reject("learning_preferences", body.learning_preferences, LEARNING_PREFERENCES)
        profile.learning_preferences = body.learning_preferences
    if body.goals is not None:
        _reject("goals", body.goals, GOALS)
        profile.goals = body.goals
    if body.subject_slugs is not None:
        slugs = list(dict.fromkeys(body.subject_slugs))
        await _validate_subjects(db, slugs)
        profile.subject_order = slugs
        # Re-seeding would wipe interest the learner earned by using the app.
        # Only genuinely new subjects get a starting weight; existing ones keep
        # whatever their behaviour has moved them to.
        seeded = _seed_interests(slugs)
        merged = dict(profile.subject_interests)
        for slug, weight in seeded.items():
            merged.setdefault(slug, weight)
        for slug in list(merged):
            if slug not in slugs:
                del merged[slug]
        profile.subject_interests = merged

    for field in ("grade", "language", "bio"):
        value = getattr(body, field)
        if value is not None:
            setattr(profile, field, value)
    if body.display_name is not None:
        user.display_name = body.display_name

    await db.flush()
    return profile
