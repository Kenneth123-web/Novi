from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy import delete, select

from novi.core.deps import DB, CurrentUser
from novi.core.errors import NotFound, ValidationFailed
from novi.core.lang import language_key
from novi.core.ratelimit import rate_limit
from novi.models import INTERACTION_TYPES, Content, ContentLike, Profile, SavedContent
from novi.schemas.common import Ok
from novi.schemas.content import (
    ContentDetail,
    ContentOut,
    FeedItem,
    FeedResponse,
    InteractionRequest,
    SaveRequest,
)
from novi.schemas.profile import ConceptOut
from novi.services import ask_service, content_service, knowledge, recommend

router = APIRouter(tags=["feed"])


@router.get("/feed", response_model=FeedResponse)
async def get_feed(
    user: CurrentUser,
    db: DB,
    limit: int = Query(default=20, ge=1, le=50),
    offset: int = Query(default=0, ge=0),
    subject: str | None = None,
) -> FeedResponse:
    ranked = await recommend.rank_feed(
        db, user_id=user.id, limit=limit + 1, offset=offset, subject_slug=subject
    )
    # One extra row is fetched purely to answer "is there more", which is
    # cheaper and more accurate than a second COUNT over the same candidates.
    has_more = len(ranked) > limit
    ranked = ranked[:limit]

    ids = [s.content.id for s in ranked]
    concepts = await content_service.concept_refs(db, ids)
    saved, liked = await content_service.user_state(db, user.id, ids)

    return FeedResponse(
        items=[
            FeedItem(
                content=content_service.to_out(s.content, concepts.get(s.content.id, [])),
                score=round(s.score, 4),
                reason=s.reason,
                is_saved=s.content.id in saved,
                is_liked=s.content.id in liked,
            )
            for s in ranked
        ],
        limit=limit,
        offset=offset,
        has_more=has_more,
    )


@router.get("/content/{content_id}", response_model=ContentDetail)
async def get_content(content_id: uuid.UUID, user: CurrentUser, db: DB) -> ContentDetail:
    content = await db.get(Content, content_id)
    if content is None:
        raise NotFound("Content not found")

    concepts = await ask_service.concepts_for_content(db, content.id)
    profile = (
        await db.execute(select(Profile).where(Profile.user_id == user.id))
    ).scalar_one_or_none()
    language = language_key(profile.language if profile else None) or "en"
    related = await content_service.related(db, content, language=language)
    ids = [content.id, *[r.id for r in related]]
    refs = await content_service.concept_refs(db, ids)
    saved, liked = await content_service.user_state(db, user.id, ids)

    return ContentDetail(
        content=content_service.to_out(content, refs.get(content.id, [])),
        concepts=[ConceptOut.model_validate(c) for c in concepts],
        related=[content_service.to_out(r, refs.get(r.id, [])) for r in related],
        is_saved=content.id in saved,
        is_liked=content.id in liked,
    )


@router.post(
    "/interactions",
    response_model=Ok,
    dependencies=[Depends(rate_limit("write", per_user=True))],
)
async def track(body: InteractionRequest, user: CurrentUser, db: DB) -> Ok:
    """The single write the client uses to report behaviour.

    One endpoint rather than one per event type: the client already knows the
    event name, and a new signal should not need a new route and a new client
    release to start being collected.
    """
    if body.kind not in INTERACTION_TYPES:
        raise ValidationFailed(
            f"Unknown interaction: {body.kind}",
            details={"field": "kind", "allowed": list(INTERACTION_TYPES)},
        )
    concept_ids = []
    if body.content_id:
        concept_ids = [c.id for c in await ask_service.concepts_for_content(db, body.content_id)]

    await knowledge.record_interaction(
        db,
        user_id=user.id,
        kind=body.kind,
        content_id=body.content_id,
        concept_id=body.concept_id,
        dwell_seconds=body.dwell_seconds,
        context=body.context,
        concept_ids=concept_ids,
    )
    return Ok()


@router.post("/content/{content_id}/save", response_model=Ok)
async def save(content_id: uuid.UUID, body: SaveRequest, user: CurrentUser, db: DB) -> Ok:
    if await db.get(Content, content_id) is None:
        raise NotFound("Content not found")
    existing = (
        await db.execute(
            select(SavedContent).where(
                SavedContent.user_id == user.id, SavedContent.content_id == content_id
            )
        )
    ).scalar_one_or_none()
    # Idempotent: a double-tap on the save button is a double-tap, not an error.
    if existing is None:
        db.add(
            SavedContent(user_id=user.id, content_id=content_id, collection=body.collection)
        )
        await knowledge.record_interaction(
            db, user_id=user.id, kind="SAVE", content_id=content_id
        )
    return Ok()


@router.delete("/content/{content_id}/save", response_model=Ok)
async def unsave(content_id: uuid.UUID, user: CurrentUser, db: DB) -> Ok:
    await db.execute(
        delete(SavedContent).where(
            SavedContent.user_id == user.id, SavedContent.content_id == content_id
        )
    )
    await knowledge.record_interaction(db, user_id=user.id, kind="UNSAVE", content_id=content_id)
    return Ok()


@router.post("/content/{content_id}/like", response_model=Ok)
async def like(content_id: uuid.UUID, user: CurrentUser, db: DB) -> Ok:
    if await db.get(Content, content_id) is None:
        raise NotFound("Content not found")
    existing = (
        await db.execute(
            select(ContentLike).where(
                ContentLike.user_id == user.id, ContentLike.content_id == content_id
            )
        )
    ).scalar_one_or_none()
    if existing is None:
        db.add(ContentLike(user_id=user.id, content_id=content_id))
        await knowledge.record_interaction(
            db, user_id=user.id, kind="LIKE", content_id=content_id
        )
    return Ok()


@router.delete("/content/{content_id}/like", response_model=Ok)
async def unlike(content_id: uuid.UUID, user: CurrentUser, db: DB) -> Ok:
    await db.execute(
        delete(ContentLike).where(
            ContentLike.user_id == user.id, ContentLike.content_id == content_id
        )
    )
    return Ok()


@router.get("/saved", response_model=list[ContentOut])
async def saved_content(user: CurrentUser, db: DB) -> list[ContentOut]:
    rows = (
        await db.execute(
            select(Content)
            .join(SavedContent, SavedContent.content_id == Content.id)
            .where(SavedContent.user_id == user.id)
            .order_by(SavedContent.created_at.desc())
        )
    ).scalars().all()
    refs = await content_service.concept_refs(db, [r.id for r in rows])
    return [content_service.to_out(r, refs.get(r.id, [])) for r in rows]
