from __future__ import annotations

import uuid

from fastapi import APIRouter, Query
from sqlalchemy import select

from novi.core.deps import DB
from novi.core.errors import NotFound
from novi.models import Concept, Subject
from novi.schemas.profile import ConceptOut, SubjectOut
from novi.services import ask_service

router = APIRouter(tags=["catalog"])


@router.get("/subjects", response_model=list[SubjectOut])
async def list_subjects(db: DB) -> list[SubjectOut]:
    rows = (await db.execute(select(Subject).order_by(Subject.sort_order, Subject.name))).scalars()
    return [SubjectOut.model_validate(r) for r in rows]


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
