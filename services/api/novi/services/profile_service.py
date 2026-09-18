"""Onboarding and profile updates."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.areas import area_slugs
from novi.core.errors import ValidationFailed
from novi.curriculum import (
    FOCUS_GOALS,
    STAGES,
    allowed_grades,
    course_for_slug,
    courses_for_grade,
    inferred_courses,
    remap_courses,
)
from novi.models import Profile, Subject, User
from novi.schemas.curriculum import CurrentCourseSelection
from novi.schemas.profile import (
    CURRICULA,
    GOALS,
    LEARNING_PREFERENCES,
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


def _unique(values: list[str]) -> list[str]:
    return list(dict.fromkeys(values))


def _clean_name(value: str) -> str:
    return " ".join(value.split())


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
    if not slugs:
        raise ValidationFailed(
            "Pick at least one subject",
            details={"field": "subject_slugs"},
        )
    known = {
        s.slug for s in (await db.execute(select(Subject).where(Subject.slug.in_(slugs)))).scalars()
    }
    unknown = [s for s in slugs if s not in known]
    if unknown:
        raise ValidationFailed(
            f"Unknown subjects: {', '.join(unknown)}",
            details={"field": "subject_slugs", "unknown": unknown},
        )


def _validate_grade(stage: str, grade: str | None) -> None:
    if not grade:
        raise ValidationFailed(
            "Grade is required",
            details={"field": "grade", "allowed": allowed_grades(stage)},
        )
    allowed = allowed_grades(stage)
    if grade not in allowed:
        raise ValidationFailed(
            "Unknown grade for this stage",
            details={"field": "grade", "allowed": allowed},
        )


def _focus_input(
    focus_subject_slugs: list[str] | None,
    weak_subject_slugs: list[str] | None,
) -> tuple[list[str], bool]:
    """Resolve the new name and its legacy alias without allowing disagreement."""
    if focus_subject_slugs is not None and weak_subject_slugs is not None:
        focus = _unique(focus_subject_slugs)
        weak = _unique(weak_subject_slugs)
        if focus != weak:
            raise ValidationFailed(
                "Focus subjects disagree with the legacy weak-subject list",
                details={"field": "focus_subject_slugs"},
            )
    explicit_new = focus_subject_slugs is not None
    values = focus_subject_slugs if explicit_new else weak_subject_slugs
    return _unique(values or []), explicit_new


def _validate_legacy_focus(subjects: list[str], focus: list[str]) -> None:
    unknown = [slug for slug in focus if slug not in subjects]
    if unknown:
        raise ValidationFailed(
            "Focus subjects must be among the subjects you picked",
            details={"field": "weak_subject_slugs", "unknown": unknown},
        )


def _validate_focus(
    focus: list[str],
    *,
    available_subjects: set[str],
    field: str,
    required: bool,
    drop_unknown: bool = False,
) -> list[str]:
    unknown = [slug for slug in focus if slug not in available_subjects]
    if unknown and drop_unknown:
        focus = [slug for slug in focus if slug in available_subjects]
    elif unknown:
        raise ValidationFailed(
            "Unknown focus subjects",
            details={"field": field, "unknown": unknown},
        )
    if required and not focus:
        raise ValidationFailed(
            "Pick at least one subject to strengthen",
            details={"field": field},
        )
    return focus


def _normalise_focus_goals(
    focus: list[str],
    goals: dict[str, str],
    *,
    require_all: bool,
) -> dict[str, str]:
    extra = [slug for slug in goals if slug not in focus]
    if extra:
        raise ValidationFailed(
            "A focus goal must belong to a selected focus subject",
            details={"field": "focus_goals", "unknown": extra},
        )
    invalid = {slug: goal for slug, goal in goals.items() if goal not in FOCUS_GOALS}
    if invalid:
        raise ValidationFailed(
            "Unknown focus goal",
            details={
                "field": "focus_goals",
                "invalid": invalid,
                "allowed": list(FOCUS_GOALS),
            },
        )
    if require_all:
        missing = [slug for slug in focus if slug not in goals]
        if missing:
            raise ValidationFailed(
                "Choose a goal for every focus subject",
                details={"field": "focus_goals", "missing": missing},
            )
    return {slug: goals[slug] for slug in focus if slug in goals}


def _normalise_focus_areas(
    subjects: list[str],
    raw: dict[str, list[str]] | None,
    *,
    require_all: bool,
    drop_unknown: bool = False,
) -> dict[str, list[str]]:
    """Validate within-subject area picks.

    A missing subject is the whole subject. Clients may send areas for only
    the chapters they care about — requiring every current class blocked
    Continue after a biology pick while math still sat blank.
    """
    incoming = raw or {}
    extra = [slug for slug in incoming if slug not in subjects]
    if extra and not drop_unknown:
        raise ValidationFailed(
            "Focus areas must belong to a subject you study or strengthen",
            details={"field": "focus_areas", "unknown": extra},
        )

    out: dict[str, list[str]] = {}
    missing: list[str] = []
    for subject in subjects:
        allowed = area_slugs(subject)
        picked = _unique(incoming.get(subject) or [])
        unknown = [slug for slug in picked if slug not in allowed]
        if unknown and drop_unknown:
            picked = [slug for slug in picked if slug in allowed]
        elif unknown:
            raise ValidationFailed(
                f"Unknown areas for {subject}",
                details={
                    "field": "focus_areas",
                    "subject": subject,
                    "unknown": unknown,
                    "allowed": sorted(allowed),
                },
            )
        if require_all and allowed and not picked:
            missing.append(subject)
        if picked:
            out[subject] = picked
    if require_all and missing:
        raise ValidationFailed(
            "Pick at least one area inside each subject",
            details={"field": "focus_areas", "missing": missing},
        )
    return out


def _normalise_courses(
    selections: list[CurrentCourseSelection],
    *,
    stage: str,
    grade: str,
    required: bool,
) -> list[dict[str, str]]:
    available = {course.slug for course in courses_for_grade(stage, grade)}
    unknown = [item.course_slug for item in selections if item.course_slug not in available]
    if unknown:
        raise ValidationFailed(
            "A selected course does not belong to this grade",
            details={"field": "current_courses", "unknown": _unique(unknown)},
        )

    out: list[dict[str, str]] = []
    indexes: dict[str, int] = {}
    for item in selections:
        name = _clean_name(item.name)
        if item.course_slug in indexes:
            # Duplicate taps collapse to one selection. If only one copy has a
            # local class name, retain the informative copy.
            index = indexes[item.course_slug]
            if name and not out[index]["name"]:
                out[index]["name"] = name
            continue
        indexes[item.course_slug] = len(out)
        out.append({"course_slug": item.course_slug, "name": name})

    if required and not out:
        raise ValidationFailed(
            "Pick at least one course you are taking",
            details={"field": "current_courses"},
        )
    return out


def _stored_courses(profile: Profile) -> list[CurrentCourseSelection]:
    parsed: list[CurrentCourseSelection] = []
    for raw in profile.current_courses or []:
        try:
            parsed.append(CurrentCourseSelection.model_validate(raw))
        except (TypeError, ValueError):
            # A malformed historical JSON object must not break /me or every
            # authenticated request. It is dropped and the subject fallback
            # below rebuilds the useful part.
            continue
    return parsed


def _subjects_for_courses(courses: list[dict[str, str]]) -> list[str]:
    subjects: list[str] = []
    for selection in courses:
        course = course_for_slug(selection["course_slug"])
        if course and course.subject_slug not in subjects:
            subjects.append(course.subject_slug)
    return subjects


def _set_subject_order(profile: Profile, slugs: list[str], *, reset: bool) -> None:
    if reset:
        profile.subject_interests = _seed_interests(slugs)
    else:
        seeded = _seed_interests(slugs)
        merged = dict(profile.subject_interests)
        for slug, weight in seeded.items():
            merged.setdefault(slug, weight)
        profile.subject_interests = {slug: merged[slug] for slug in slugs}
    profile.subject_order = slugs


async def apply_onboarding(
    db: AsyncSession, user: User, body: OnboardingRequest
) -> Profile:
    if body.stage not in STAGES:
        raise ValidationFailed("Unknown stage", details={"field": "stage", "allowed": STAGES})
    _validate_grade(body.stage, body.grade)
    if body.curriculum and body.curriculum not in CURRICULA:
        raise ValidationFailed(
            "Unknown curriculum", details={"field": "curriculum", "allowed": CURRICULA}
        )
    _reject("learning_preferences", body.learning_preferences, LEARNING_PREFERENCES)
    _reject("goals", body.goals, GOALS)

    available_subjects = {
        course.subject_slug for course in courses_for_grade(body.stage, body.grade)
    }
    if body.current_courses is not None:
        current_courses = _normalise_courses(
            body.current_courses,
            stage=body.stage,
            grade=body.grade,
            required=True,
        )
        course_subjects = _subjects_for_courses(current_courses)
        if body.subject_slugs is not None:
            legacy_subjects = _unique(body.subject_slugs)
            await _validate_subjects(db, legacy_subjects)
            if legacy_subjects != course_subjects:
                raise ValidationFailed(
                    "Subjects disagree with the selected courses",
                    details={"field": "subject_slugs"},
                )
    else:
        legacy_subjects = _unique(body.subject_slugs or [])
        await _validate_subjects(db, legacy_subjects)
        current_courses = inferred_courses(body.stage, body.grade, legacy_subjects)
        course_subjects = _subjects_for_courses(current_courses)

    focus, explicit_focus = _focus_input(
        body.focus_subject_slugs,
        body.weak_subject_slugs,
    )
    if not explicit_focus:
        _validate_legacy_focus(course_subjects, focus)
    focus = _validate_focus(
        focus,
        available_subjects=available_subjects,
        field="focus_subject_slugs" if explicit_focus else "weak_subject_slugs",
        required=True,
    )
    focus_goals = _normalise_focus_goals(
        focus,
        body.focus_goals,
        require_all=explicit_focus,
    )
    area_subjects = _unique(course_subjects + focus)
    focus_areas = _normalise_focus_areas(
        area_subjects,
        body.focus_areas,
        require_all=False,
    )
    subject_order = course_subjects + [slug for slug in focus if slug not in course_subjects]
    await _validate_subjects(db, subject_order)

    profile = await get_or_create(db, user)
    profile.stage = body.stage
    profile.grade = body.grade
    profile.curriculum = body.curriculum
    _set_subject_order(profile, subject_order, reset=True)
    profile.weak_subjects = focus
    profile.current_courses = current_courses
    profile.focus_goals = focus_goals
    profile.focus_areas = focus_areas
    profile.learning_preferences = list(body.learning_preferences)
    profile.goals = list(body.goals)
    profile.language = body.language
    profile.interests_decayed_at = datetime.now(UTC)

    user.onboarded_at = datetime.now(UTC)
    await db.flush()
    return profile


async def update(db: AsyncSession, user: User, body: ProfileUpdate) -> Profile:
    profile = await get_or_create(db, user)

    effective_stage = body.stage if body.stage is not None else profile.stage
    effective_grade = body.grade if body.grade is not None else profile.grade
    learning_fields = {
        "stage",
        "grade",
        "curriculum",
        "current_courses",
        "focus_subject_slugs",
        "focus_goals",
        "focus_areas",
        "subject_slugs",
        "weak_subject_slugs",
    }
    learning_change = bool(body.model_fields_set & learning_fields)
    if learning_change:
        if effective_stage not in STAGES:
            raise ValidationFailed(
                "Unknown stage",
                details={"field": "stage", "allowed": STAGES},
            )
        _validate_grade(effective_stage, effective_grade)

    if "curriculum" in body.model_fields_set:
        if body.curriculum is not None and body.curriculum not in CURRICULA:
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

    if learning_change:
        assert effective_stage is not None and effective_grade is not None
        available_subjects = {
            course.subject_slug for course in courses_for_grade(effective_stage, effective_grade)
        }
        grade_changed = (
            effective_stage != profile.stage or effective_grade != profile.grade
        )

        if body.current_courses is not None:
            current_courses = _normalise_courses(
                body.current_courses,
                stage=effective_stage,
                grade=effective_grade,
                required=True,
            )
        elif body.subject_slugs is not None:
            legacy_subjects = _unique(body.subject_slugs)
            await _validate_subjects(db, legacy_subjects)
            current_courses = inferred_courses(
                effective_stage,
                effective_grade,
                legacy_subjects,
            )
        elif grade_changed:
            current_courses = remap_courses(
                effective_stage,
                effective_grade,
                [item.model_dump() for item in _stored_courses(profile)],
                extra_subjects=list(profile.subject_order),
            )
        else:
            current_courses = _normalise_courses(
                _stored_courses(profile),
                stage=effective_stage,
                grade=effective_grade,
                required=False,
            )
            if not current_courses:
                current_courses = inferred_courses(
                    effective_stage,
                    effective_grade,
                    list(profile.subject_order),
                )

        course_subjects = _subjects_for_courses(current_courses)
        if not current_courses:
            raise ValidationFailed(
                "Pick at least one course you are taking",
                details={"field": "current_courses"},
            )
        if body.current_courses is not None and body.subject_slugs is not None:
            legacy_subjects = _unique(body.subject_slugs)
            await _validate_subjects(db, legacy_subjects)
            if legacy_subjects != course_subjects:
                raise ValidationFailed(
                    "Subjects disagree with the selected courses",
                    details={"field": "subject_slugs"},
                )

        focus_changed = (
            body.focus_subject_slugs is not None
            or body.weak_subject_slugs is not None
        )
        if focus_changed:
            focus, explicit_focus = _focus_input(
                body.focus_subject_slugs,
                body.weak_subject_slugs,
            )
            if not explicit_focus:
                _validate_legacy_focus(course_subjects, focus)
            focus = _validate_focus(
                focus,
                available_subjects=available_subjects,
                field=(
                    "focus_subject_slugs"
                    if explicit_focus
                    else "weak_subject_slugs"
                ),
                required=True,
            )
        else:
            explicit_focus = False
            focus = _validate_focus(
                _unique(list(profile.weak_subjects)),
                available_subjects=available_subjects,
                field="focus_subject_slugs",
                required=False,
                drop_unknown=grade_changed,
            )

        raw_goals = (
            body.focus_goals
            if body.focus_goals is not None
            else dict(profile.focus_goals)
        )
        focus_goals = _normalise_focus_goals(
            focus,
            raw_goals,
            require_all=focus_changed and explicit_focus,
        )
        area_subjects = _unique(course_subjects + focus)
        raw_areas = (
            body.focus_areas
            if body.focus_areas is not None
            else dict(profile.focus_areas or {})
        )
        focus_areas = _normalise_focus_areas(
            area_subjects,
            raw_areas,
            require_all=False,
            drop_unknown=body.focus_areas is None,
        )
        subject_order = course_subjects + [
            slug for slug in focus if slug not in course_subjects
        ]
        await _validate_subjects(db, subject_order)

        profile.stage = effective_stage
        profile.grade = effective_grade
        profile.current_courses = current_courses
        profile.weak_subjects = focus
        profile.focus_goals = focus_goals
        profile.focus_areas = focus_areas
        _set_subject_order(profile, subject_order, reset=False)

    for field in ("language", "bio"):
        value = getattr(body, field)
        if value is not None:
            setattr(profile, field, value)
    if body.display_name is not None:
        user.display_name = body.display_name

    await db.flush()
    return profile
