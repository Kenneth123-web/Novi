from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select

from novi.core.deps import DB, CurrentUser
from novi.core.errors import NotFound, ValidationFailed
from novi.core.ratelimit import rate_limit
from novi.models import Concept, Discussion, Question, Subject
from novi.schemas.ai import ASK_MODES, AskRequest, AskResponse, SummarizeRequest
from novi.schemas.common import Ok
from novi.schemas.content import DiscussionOut
from novi.schemas.profile import ConceptOut
from novi.services import ask_service, content_service, discussion_service

router = APIRouter(tags=["ask"])


@router.post(
    "/ask",
    response_model=AskResponse,
    dependencies=[Depends(rate_limit("ai", per_user=True))],
)
async def ask(body: AskRequest, user: CurrentUser, db: DB) -> AskResponse:
    """Explain, then hand back the rabbit hole in the same response.

    A second round trip for the discovery rail would put a spinner exactly
    where the learner's momentum is.
    """
    if body.mode not in ASK_MODES:
        raise ValidationFailed(
            f"Unknown mode: {body.mode}", details={"field": "mode", "allowed": ASK_MODES}
        )

    question, explanation, rail = await ask_service.ask(
        db,
        user=user,
        question=body.question,
        mode=body.mode,
        content_id=body.content_id,
        concept_id=body.concept_id,
    )

    watch, read = rail["watch"], rail["read"]
    refs = await content_service.concept_refs(db, [c.id for c in watch + read])
    return AskResponse(
        question_id=question.id,
        explanation=explanation,
        watch=[content_service.to_out(c, refs.get(c.id, [])) for c in watch],
        read=[content_service.to_out(c, refs.get(c.id, [])) for c in read],
        discuss=[DiscussionOut.model_validate(d) for d in rail["discuss"]],
        related_concepts=rail["related_concepts"],
    )


@router.get("/questions", response_model=list[dict])
async def my_questions(
    user: CurrentUser, db: DB, limit: int = Query(20, ge=1, le=100)
) -> list[dict]:
    rows = (
        await db.execute(
            select(Question)
            .where(Question.user_id == user.id)
            .order_by(Question.created_at.desc())
            .limit(limit)
        )
    ).scalars().all()
    return [
        {
            "id": str(q.id),
            "text": q.text_,
            "mode": q.mode,
            "created_at": q.created_at,
            "answer": q.answer.payload if q.answer else None,
        }
        for q in rows
    ]


@router.get("/discussions", response_model=list[DiscussionOut])
async def list_discussions(
    db: DB,
    concept_id: uuid.UUID | None = None,
    limit: int = Query(default=10, ge=1, le=50),
) -> list[DiscussionOut]:
    stmt = select(Discussion).order_by(Discussion.upvotes.desc()).limit(limit)
    if concept_id:
        stmt = stmt.where(Discussion.concept_id == concept_id)
    rows = (await db.execute(stmt)).scalars().all()
    return [DiscussionOut.model_validate(d) for d in rows]


@router.get("/discussions/{discussion_id}", response_model=DiscussionOut)
async def get_discussion(discussion_id: uuid.UUID, db: DB) -> DiscussionOut:
    row = await db.get(Discussion, discussion_id)
    if row is None:
        raise NotFound("Discussion not found")
    return DiscussionOut.model_validate(row)


@router.post(
    "/discussions/{discussion_id}/summarize",
    dependencies=[Depends(rate_limit("ai", per_user=True))],

)
async def summarize(discussion_id: uuid.UUID, user: CurrentUser, db: DB) -> dict:
    return await discussion_service.summarize(db, discussion_id)


@router.post(
    "/discussions/{discussion_id}/translate",
    dependencies=[Depends(rate_limit("ai", per_user=True))],

)
async def translate(
    discussion_id: uuid.UUID, body: SummarizeRequest, user: CurrentUser, db: DB
) -> dict:
    target = body.translate_to or "English"
    return await discussion_service.translate(db, discussion_id, target_language=target)


@router.get("/search")
async def search(
    user: CurrentUser,
    db: DB,
    q: str = Query(min_length=1, max_length=200),
    limit: int = Query(default=20, ge=1, le=50),
    _: None = Depends(rate_limit("search", per_user=True)),
) -> dict:
    """Universal search: a concept, then content, then discussions.

    Deliberately does NOT call the model. Search has to be instant, and the
    explanation is one tap away on the concept card — paying two seconds of
    model latency on every keystroke-completed query would make the whole
    feature feel broken.
    """
    cleaned = q.strip()
    if not cleaned:
        return {"query": q, "concept": None, "content": [], "discussions": []}

    concept = (
        await db.execute(select(Concept).where(Concept.name.ilike(cleaned)).limit(1))
    ).scalar_one_or_none()
    if concept is None:
        concept = (
            await db.execute(select(Concept).where(Concept.name.ilike(f"%{cleaned}%")).limit(1))
        ).scalar_one_or_none()

    rows = await content_service.search(db, query=cleaned, limit=limit)
    refs = await content_service.concept_refs(db, [r.id for r in rows])

    discussions = (
        await db.execute(
            select(Discussion)
            .where(Discussion.title.ilike(f"%{cleaned}%") | Discussion.body.ilike(f"%{cleaned}%"))
            .order_by(Discussion.upvotes.desc())
            .limit(5)
        )
    ).scalars().all()

    subject = await db.get(Subject, concept.subject_id) if concept else None
    return {
        "query": cleaned,
        "concept": (
            {
                **ConceptOut.model_validate(concept).model_dump(mode="json"),
                "subject_name": subject.name if subject else None,
            }
            if concept
            else None
        ),
        "content": [
            content_service.to_out(r, refs.get(r.id, [])).model_dump(mode="json") for r in rows
        ],
        "discussions": [
            DiscussionOut.model_validate(d).model_dump(mode="json") for d in discussions
        ],
    }


@router.post("/questions/{question_id}/feedback", response_model=Ok)
async def feedback(question_id: uuid.UUID, value: int, user: CurrentUser, db: DB) -> Ok:
    question = await db.get(Question, question_id)
    if question is None or question.user_id != user.id:
        raise NotFound("Question not found")
    if question.answer is None:
        raise NotFound("This question has no answer yet")
    if value not in (-1, 1):
        raise ValidationFailed("Feedback must be 1 or -1", details={"field": "value"})
    question.answer.feedback = value
    return Ok()
