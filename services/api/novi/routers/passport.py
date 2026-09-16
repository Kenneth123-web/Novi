from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from sqlalchemy import select

from novi.core.deps import DB, CurrentUser
from novi.core.errors import NotFound
from novi.core.ratelimit import rate_limit
from novi.models import Concept, Project, ProjectConcept
from novi.schemas.ai import (
    QuizOut,
    QuizQuestionOut,
    QuizRequest,
    QuizResultOut,
    QuizSubmission,
    StampOut,
)
from novi.services import knowledge, passport_service, quiz_service

router = APIRouter(tags=["passport"])


# ── Quizzes ──────────────────────────────────────────────────────────────────


@router.post(
    "/quiz",
    response_model=QuizOut,
    dependencies=[Depends(rate_limit("ai", per_user=True))],
)
async def create_quiz(body: QuizRequest, user: CurrentUser, db: DB) -> QuizOut:
    quiz, concept = await quiz_service.generate(
        db,
        user=user,
        concept_id=body.concept_id,
        count=body.count,
        difficulty=body.difficulty,
    )
    return QuizOut(
        id=quiz.id,
        concept_id=concept.id,
        concept_name=concept.name,
        difficulty=quiz.difficulty,
        # QuizQuestionOut has no correct_index — the key stays server-side
        # until the learner has answered.
        questions=[
            QuizQuestionOut(id=q.id, ordinal=q.ordinal, prompt=q.prompt, options=q.options)
            for q in quiz.questions
        ],
    )


@router.post("/quiz/{quiz_id}/submit", response_model=QuizResultOut)
async def submit_quiz(
    quiz_id: uuid.UUID, body: QuizSubmission, user: CurrentUser, db: DB
) -> QuizResultOut:
    quiz, graded, score, mastery, stamps = await quiz_service.submit(
        db, user=user, quiz_id=quiz_id, answers=body.answers
    )
    return QuizResultOut(
        quiz_id=quiz.id,
        score=round(score, 3),
        correct=sum(1 for g in graded if g.is_correct),
        total=len(quiz.questions),
        answers=graded,
        concept_mastery=mastery,
        new_stamps=stamps,
    )


# ── Passport ─────────────────────────────────────────────────────────────────


@router.get("/passport")
async def passport(user: CurrentUser, db: DB) -> dict:
    return await passport_service.overview(db, user.id)


class MarkLearned(BaseModel):
    concept_id: uuid.UUID


@router.post("/passport/learn")
async def mark_learned(body: MarkLearned, user: CurrentUser, db: DB) -> dict:
    """Let the learner assert they know something.

    Self-reporting is weaker evidence than a quiz, so it stops at "learned" and
    cannot reach "mastered" — mastery has to be earned against questions.
    """
    concept = await db.get(Concept, body.concept_id)
    if concept is None:
        raise NotFound("Concept not found")

    await knowledge.record_interaction(
        db, user_id=user.id, kind="MARK_LEARNED", concept_id=concept.id
    )
    stamp = await knowledge.award_stamp(
        db,
        user_id=user.id,
        kind="concept",
        key=concept.slug,
        title=concept.name,
        subtitle="Learned",
        icon="checkmark.seal",
    )
    progress = await knowledge.get_or_create_progress(db, user.id, concept.id)
    return {
        "concept_id": str(concept.id),
        "mastery": progress.mastery,
        "new_stamps": (
            [StampOut(kind=stamp.kind, key=stamp.key, title=stamp.title,
                      subtitle=stamp.subtitle, icon=stamp.icon).model_dump()]
            if stamp
            else []
        ),
    }


# ── Projects ─────────────────────────────────────────────────────────────────


class ProjectIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    description: str = Field(default="", max_length=4000)
    skills: list[str] = Field(default_factory=list, max_length=20)
    concept_ids: list[uuid.UUID] = Field(default_factory=list, max_length=30)
    status: str = "in_progress"
    progress: float = Field(default=0.0, ge=0.0, le=1.0)


def _project_out(project: Project, concepts: list[Concept]) -> dict:
    return {
        "id": str(project.id),
        "title": project.title,
        "description": project.description,
        "skills": project.skills,
        "status": project.status,
        "progress": project.progress,
        "cover_seed": project.cover_seed,
        "created_at": project.created_at,
        "concepts": [{"id": str(c.id), "slug": c.slug, "name": c.name} for c in concepts],
    }


async def _concepts_for(db: DB, project: Project) -> list[Concept]:
    ids = [link.concept_id for link in project.concept_links]
    if not ids:
        return []
    return list((await db.execute(select(Concept).where(Concept.id.in_(ids)))).scalars())


@router.get("/projects")
async def list_projects(user: CurrentUser, db: DB) -> list[dict]:
    rows = (
        await db.execute(
            select(Project).where(Project.user_id == user.id).order_by(Project.created_at.desc())
        )
    ).scalars().all()
    return [_project_out(p, await _concepts_for(db, p)) for p in rows]


@router.post("/projects", status_code=201)
async def create_project(body: ProjectIn, user: CurrentUser, db: DB) -> dict:
    project = Project(
        user_id=user.id,
        title=body.title,
        description=body.description,
        skills=body.skills,
        status=body.status,
        progress=body.progress,
        cover_seed=uuid.uuid4().hex[:12],
    )
    db.add(project)
    await db.flush()

    for concept_id in dict.fromkeys(body.concept_ids):
        if await db.get(Concept, concept_id) is not None:
            db.add(ProjectConcept(project_id=project.id, concept_id=concept_id))
    await db.flush()

    await knowledge.record_interaction(db, user_id=user.id, kind="PROJECT_CREATE")
    if body.status == "completed":
        await knowledge.award_stamp(
            db,
            user_id=user.id,
            kind="project",
            key=str(project.id),
            title=project.title,
            subtitle="Project completed",
            icon="hammer",
        )
    await db.refresh(project)
    return _project_out(project, await _concepts_for(db, project))


@router.patch("/projects/{project_id}")
async def update_project(
    project_id: uuid.UUID, body: ProjectIn, user: CurrentUser, db: DB
) -> dict:
    project = await db.get(Project, project_id)
    if project is None or project.user_id != user.id:
        raise NotFound("Project not found")

    project.title = body.title
    project.description = body.description
    project.skills = body.skills
    project.status = body.status
    project.progress = body.progress

    if body.status == "completed":
        await knowledge.award_stamp(
            db,
            user_id=user.id,
            kind="project",
            key=str(project.id),
            title=project.title,
            subtitle="Project completed",
            icon="hammer",
        )
    await db.flush()
    await db.refresh(project)
    return _project_out(project, await _concepts_for(db, project))
