from __future__ import annotations

import uuid

from fastapi import APIRouter, Query
from sqlalchemy import select

from novi.areas import all_subjects_payload, subject_areas, subject_as_dict
from novi.core.deps import DB
from novi.core.errors import NotFound, ValidationFailed
from novi.curriculum import FRAMEWORK_NOTE, GRADE_SPECS, STAGES, courses_for_grade, grade_spec
from novi.models import Concept, Subject
from novi.schemas.curriculum import (
    CurriculumCourseOut,
    GradeCurriculumOut,
    GradeSpecOut,
    SubjectAreasOut,
)
from novi.schemas.profile import ConceptOut, SubjectOut
from novi.services import ask_service

router = APIRouter(tags=["catalog"])


@router.get("/subjects", response_model=list[SubjectOut])
async def list_subjects(db: DB) -> list[SubjectOut]:
    rows = (await db.execute(select(Subject).order_by(Subject.sort_order, Subject.name))).scalars()
    return [SubjectOut.model_validate(r) for r in rows]


@router.get("/curriculum", response_model=list[GradeSpecOut])
async def list_grades() -> list[GradeSpecOut]:
    """Every grade the product supports. Customization reads this list."""
    return [
        GradeSpecOut(
            stage=spec.stage,
            slug=spec.slug,
            label=spec.label,
            age_range=spec.age_range,
            level=spec.level,
        )
        for spec in GRADE_SPECS
    ]


@router.get("/curriculum/{stage}/{grade}", response_model=GradeCurriculumOut)
async def grade_curriculum(stage: str, grade: str, db: DB) -> GradeCurriculumOut:
    """The complete Novi course map for one supported grade.

    Customization and the passport both read this same deterministic catalog;
    neither client labels nor database seed order can create a second version.
    """
    spec = grade_spec(stage, grade)
    if spec is None:
        raise ValidationFailed(
            "Unknown grade for this stage",
            details={"field": "grade", "stage": stage, "allowed_stages": STAGES},
        )

    subjects = {
        subject.slug: subject for subject in (await db.execute(select(Subject))).scalars()
    }
    missing = [
        course.subject_slug
        for course in courses_for_grade(stage, grade)
        if course.subject_slug not in subjects
    ]
    if missing:
        raise ValidationFailed(
            "The curriculum catalog is not seeded",
            details={"field": "subjects", "missing": missing},
        )

    return GradeCurriculumOut(
        stage=stage,
        grade=grade,
        grade_label=spec.label,
        age_range=spec.age_range,
        framework_note=FRAMEWORK_NOTE,
        courses=[
            CurriculumCourseOut(
                slug=course.slug,
                subject_slug=course.subject_slug,
                subject_name=subjects[course.subject_slug].name,
                subject_description=subjects[course.subject_slug].description,
                icon=subjects[course.subject_slug].icon,
                accent=subjects[course.subject_slug].accent,
                name=course.name,
                description=course.description,
                skills=list(course.skills),
                requirement=course.requirement,
                level=course.level,
            )
            for course in courses_for_grade(stage, grade)
        ],
    )


@router.get("/areas", response_model=list[SubjectAreasOut])
async def list_areas() -> list[SubjectAreasOut]:
    """Every within-subject area the product can personalise on.

    Biology is not one feed. This list is what onboarding and the profile
    editor render; ranking and the passport both key off the same slugs.
    """
    return [SubjectAreasOut.model_validate(item) for item in all_subjects_payload()]


@router.get("/areas/{subject_slug}", response_model=SubjectAreasOut)
async def subject_area_catalog(subject_slug: str) -> SubjectAreasOut:
    item = subject_areas(subject_slug)
    if item is None:
        raise NotFound("Subject not found")
    return SubjectAreasOut.model_validate(subject_as_dict(item))


@router.get("/concepts", response_model=list[ConceptOut])
async def list_concepts(
    db: DB,
    subject_slug: str | None = None,
    limit: int = Query(default=100, ge=1, le=500),
) -> list[ConceptOut]:
    stmt = select(Concept).order_by(Concept.sort_order, Concept.name).limit(limit)
    if subject_slug:
        stmt = stmt.join(Subject).where(Subject.slug == subject_slug)
    rows = (await db.execute(stmt)).scalars()
    return [ConceptOut.model_validate(r) for r in rows]


@router.get("/concepts/{concept_id}")
async def get_concept(concept_id: uuid.UUID, db: DB) -> dict:
    concept = await db.get(Concept, concept_id)
    if concept is None:
        raise NotFound("Concept not found")
    subject = await db.get(Subject, concept.subject_id)
    neighbours = await ask_service.concept_neighbours(db, concept_id)
    return {
        "concept": ConceptOut.model_validate(concept).model_dump(),
        "subject": SubjectOut.model_validate(subject).model_dump() if subject else None,
        "next": [ConceptOut.model_validate(c).model_dump() for c in neighbours],
    }
