from __future__ import annotations

import json
import uuid
from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from novi.schemas.common import ORMModel
from novi.schemas.profile import ConceptOut


class ConceptRef(BaseModel):
    id: uuid.UUID
    slug: str
    name: str


class ContentOut(ORMModel):
    id: uuid.UUID
    platform: str
    title: str
    description: str
    creator: str
    url: str | None = None
    media_url: str | None = None
    thumbnail_url: str | None = None
    # The masonry has to know a card's height before laying it out, so the
    # ratio ships with the item rather than being measured after load.
    thumbnail_ratio: float = 0.75
    media_kind: str
    language: str
    duration_seconds: int | None = None
    topic: str
    tags: list[str] = Field(default_factory=list)
    likes: int = 0
    comments: int = 0
    difficulty: int = 2
    # True while the store is seeded with stand-ins rather than ingested items.
    # The client shows a marker; pretending otherwise would make placeholder
    # content indistinguishable from the real thing.
    is_sample: bool = False
    subject_id: uuid.UUID | None = None
    published_at: datetime | None = None
    concepts: list[ConceptRef] = Field(default_factory=list)


class FeedItem(BaseModel):
    content: ContentOut
    score: float
    reason: str
    # Saved / liked travel with the card so the feed does not need N extra
    # round trips to render its own buttons correctly.
    is_saved: bool = False
    is_liked: bool = False


class FeedResponse(BaseModel):
    items: list[FeedItem]
    limit: int
    offset: int
    has_more: bool


class ContentDetail(BaseModel):
    content: ContentOut
    concepts: list[ConceptOut] = Field(default_factory=list)
    related: list[ContentOut] = Field(default_factory=list)
    is_saved: bool = False
    is_liked: bool = False
    reason: str = ""


class InteractionRequest(BaseModel):
    kind: str = Field(min_length=1, max_length=24)
    content_id: uuid.UUID | None = None
    concept_id: uuid.UUID | None = None
    dwell_seconds: int = Field(default=0, ge=0, le=86_400)
    context: dict = Field(default_factory=dict)

    @field_validator("context")
    @classmethod
    def _bounded_context(cls, value: dict) -> dict:
        if len(json.dumps(value, default=str).encode()) > 8_192:
            raise ValueError("context must be at most 8192 bytes")
        return value


class SaveRequest(BaseModel):
    collection: str = Field(default="", max_length=80)


class DiscussionCommentOut(ORMModel):
    id: uuid.UUID
    author: str
    body: str
    upvotes: int


class DiscussionOut(ORMModel):
    id: uuid.UUID
    platform: str
    community: str
    title: str
    body: str
    author: str
    url: str | None = None
    language: str
    upvotes: int
    comment_count: int
    is_sample: bool = False
    comments: list[DiscussionCommentOut] = Field(default_factory=list)
    translation: dict | None = None
    summary: dict | None = None
