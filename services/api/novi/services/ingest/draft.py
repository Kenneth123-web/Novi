"""A fetched tutorial waiting to be matched to a concept and stored."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Draft:
    platform: str
    external_id: str
    title: str
    description: str
    creator: str
    url: str
    media_kind: str = "video"
    language: str = "en"
    likes: int = 0
    comments: int = 0
    duration_seconds: int | None = None
    thumbnail_url: str | None = None
    thumbnail_ratio: float = 0.75
    published_at: datetime | None = None
    community: str = ""
    extra: dict = field(default_factory=dict)
