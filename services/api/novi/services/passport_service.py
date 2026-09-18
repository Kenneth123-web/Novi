"""The Learning Passport: what the learner has actually done."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.areas import area_name
from novi.curriculum import (
    FRAMEWORK_NOTE,
    courses_for_grade,
    focus_goal_label,
    grade_spec,
    inferred_courses,
)
from novi.models import (
    MASTERY_RANK,
    Concept,
    Interaction,
    LearningProgress,
    PassportStamp,
    Profile,
    Project,
    Quiz,
    Subject,
)

# What counts as "covered" in the headline number. `discovered` does not: the
# passport is a record of learning, and a card scrolled past is not learning.
COVERED_FROM = MASTERY_RANK["explored"]


def _saved_courses(profile: Profile) -> tuple[list[dict[str, str]], str]:
    """Return valid, de-duplicated selections with a legacy fallback."""
    available = {
        course.slug
        for course in courses_for_grade(profile.stage or "", profile.grade or "")
    }
    selected: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in profile.current_courses or []:
        if not isinstance(raw, dict):
            continue
        slug = raw.get("course_slug")
        if not isinstance(slug, str) or slug not in available or slug in seen:
            continue
        seen.add(slug)
        name = raw.get("name", "")
        selected.append(
            {
                "course_slug": slug,
                "name": " ".join(name.split()) if isinstance(name, str) else "",
            }
        )
    if selected:
        return selected, "saved"
    return (
        inferred_courses(
            profile.stage or "",
            profile.grade or "",
            list(profile.subject_order),
        ),
        "inferred",
    )


def _course_status(rows: list[tuple[Concept, LearningProgress | None]]) -> str:
    if not rows or not any(progress for _, progress in rows):
        return "not_started"
    ranks = [
        MASTERY_RANK.get(progress.mastery, 0)
        for _, progress in rows
        if progress is not None
    ]
    if ranks and all(rank >= MASTERY_RANK["mastered"] for rank in ranks):
        return "mastered"
    if ranks and all(rank >= MASTERY_RANK["learned"] for rank in ranks):
        return "learned"
    return "in_progress"


def _course_reason(
    *,
    lane: str,
    subject_name: str,
    grade_label: str,
    focus_goal: str | None,
    is_current: bool,
    area_names: list[str],
) -> str:
    if lane == "focus":
        goal = focus_goal_label(focus_goal)
        if goal:
            prefix = "Current course; " if is_current else ""
            reason = f"{prefix}{goal} in {subject_name}, based on your learning focus."
        else:
            reason = f"{subject_name} is one of the subjects you chose to strengthen."
    elif lane == "current":
        reason = "Included because you said you are taking this course now."
    elif lane == "required":
        reason = f"A core course in Novi's complete {grade_label} learning map."
    else:
        reason = f"Recommended to broaden the {grade_label} learning map."
    if area_names:
        reason = f"{reason} Focusing on {', '.join(area_names)}."
    return reason


def _curriculum_map(
    *,
    profile: Profile | None,
    subjects: dict[uuid.UUID, Subject],
    concepts: list[Concept],
    progress_by_concept: dict[uuid.UUID, LearningProgress],
) -> tuple[dict | None, list[dict]]:
    if profile is None:
        return None, []
    spec = grade_spec(profile.stage or "", profile.grade or "")
    if spec is None:
        return None, []

    selections, source = _saved_courses(profile)
    names = {
        item["course_slug"]: item["name"]
        for item in selections
        if item["name"]
    }
    current = {item["course_slug"] for item in selections}
    focus = {
        slug
        for slug in profile.weak_subjects or []
        if any(course.subject_slug == slug for course in courses_for_grade(spec.stage, spec.slug))
    }
    focus_goals = {
        slug: goal
        for slug, goal in (profile.focus_goals or {}).items()
        if slug in focus
    }
    stored_areas = profile.focus_areas or {}
    focus_areas = {
        slug: [area for area in stored_areas.get(slug, []) if isinstance(area, str) and area]
        for slug in {course.subject_slug for course in courses_for_grade(spec.stage, spec.slug)}
        if stored_areas.get(slug)
    }
    subject_by_slug = {subject.slug: subject for subject in subjects.values()}
    concepts_by_subject: dict[uuid.UUID, list[Concept]] = {}
    for concept in concepts:
        concepts_by_subject.setdefault(concept.subject_id, []).append(concept)

    course_map: list[dict] = []
    for course in courses_for_grade(spec.stage, spec.slug):
        subject = subject_by_slug.get(course.subject_slug)
        if subject is None:
            continue
        subject_concepts = sorted(
            concepts_by_subject.get(subject.id, []),
            key=lambda concept: (concept.difficulty, concept.sort_order, concept.name),
        )
        relevant = [
            concept for concept in subject_concepts if concept.difficulty <= course.level
        ]
        if not relevant and subject_concepts:
            minimum = min(concept.difficulty for concept in subject_concepts)
            relevant = [
                concept for concept in subject_concepts if concept.difficulty == minimum
            ]

        rows = [
            (concept, progress_by_concept.get(concept.id))
            for concept in relevant
        ]
        ranks = [
            MASTERY_RANK.get(progress.mastery, 0) if progress else 0
            for _, progress in rows
        ]
        max_rank = MASTERY_RANK["mastered"]
        progress_value = (
            sum(rank / max_rank for rank in ranks) / len(rows)
            if rows
            else 0.0
        )
        covered = sum(rank >= COVERED_FROM for rank in ranks)
        learned = sum(rank >= MASTERY_RANK["learned"] for rank in ranks)
        is_current = course.slug in current
        is_focus = course.subject_slug in focus
        lane = (
            "focus"
            if is_focus
            else "current"
            if is_current
            else course.requirement
        )
        focus_goal = focus_goals.get(course.subject_slug)
        area_slugs = (
            focus_areas.get(course.subject_slug, [])
            if is_current or is_focus
            else []
        )
        area_payload = [
            {"slug": slug, "name": area_name(course.subject_slug, slug)}
            for slug in area_slugs
        ]
        area_names = [item["name"] for item in area_payload]
        course_map.append(
            {
                "slug": course.slug,
                "subject_slug": subject.slug,
                "subject_name": subject.name,
                "icon": subject.icon,
                "accent": subject.accent,
                "name": names.get(course.slug) or course.name,
                "canonical_name": course.name,
                "description": course.description,
                "skills": list(course.skills),
                "requirement": course.requirement,
                "lane": lane,
                "is_current": is_current,
                "is_focus": is_focus,
                "focus_goal": focus_goal_label(focus_goal),
                "focus_areas": area_payload,
                "recommendation_reason": _course_reason(
                    lane=lane,
                    subject_name=subject.name,
                    grade_label=spec.label,
                    focus_goal=focus_goal,
                    is_current=is_current,
                    area_names=area_names if (is_current or is_focus) else [],
                ),
                "status": _course_status(rows),
                "progress": round(progress_value, 3),
                "learned_concepts": learned,
                "covered_concepts": covered,
                "total_concepts": len(rows),
                "concepts": [
                    {
                        "id": str(concept.id),
                        "slug": concept.slug,
                        "name": concept.name,
                        "mastery": progress.mastery if progress else "not_started",
                        "confidence": round(progress.confidence, 2) if progress else 0.0,
                    }
                    for concept, progress in rows
                ],
            }
        )

    lane_order = {"focus": 0, "current": 1, "required": 2, "recommended": 3}
    course_map.sort(key=lambda course: lane_order[course["lane"]])
    context = {
        "stage": spec.stage,
        "grade": spec.slug,
        "grade_label": spec.label,
        "age_range": spec.age_range,
        "framework": profile.curriculum,
        "framework_note": FRAMEWORK_NOTE,
        "selection_source": source,
        "focus_subjects": list(focus),
        "focus_goals": focus_goals,
    }
    return context, course_map


async def overview(db: AsyncSession, user_id: uuid.UUID) -> dict:
    progress = (
        await db.execute(
            select(LearningProgress).where(LearningProgress.user_id == user_id)
        )
    ).scalars().all()

    progress_by_concept = {row.concept_id: row for row in progress}
    concepts = (await db.execute(select(Concept))).scalars().all()
    by_id = {c.id: c for c in concepts}
    subjects = {s.id: s for s in (await db.execute(select(Subject))).scalars()}
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user_id))
    ).scalar_one_or_none()
    curriculum_context, course_map = _curriculum_map(
        profile=profile,
        subjects=subjects,
        concepts=list(concepts),
        progress_by_concept=progress_by_concept,
    )

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
        "curriculum": curriculum_context,
        "course_map": course_map,
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
