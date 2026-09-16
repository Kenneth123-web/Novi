"""Upsert ingested tutorials. Natural key is (platform, external_id)."""

from __future__ import annotations

import math
from datetime import UTC, datetime

from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.models import Content, ContentConcept, Discussion, DiscussionComment
from novi.services.ingest.draft import Draft
from novi.services.ingest.match import CatalogEntry, best


def _looks_cjk(text: str) -> bool:
    return any("\u4e00" <= ch <= "\u9fff" for ch in text)


def _quality(draft: Draft) -> float:
    # Engagement is heavy-tailed. Log keeps a viral video from owning the feed
    # while still beating a 12-view upload.
    return round(min(0.95, 0.42 + math.log10(max(draft.likes, 1) + 1) / 8), 3)


def _english_title(draft: Draft, entry: CatalogEntry) -> str:
    """Keep the original, but lead with the catalog name when the title is CJK.

    Full AI translation runs in a second pass; this is what makes a Chinese
    Bilibili hit readable in an English feed the moment it lands.
    """
    title = (draft.title or "").strip()
    if not title:
        return f"{entry.concept.name} tutorial"
    if _looks_cjk(title):
        return f"{entry.concept.name} — {title[:180]}"
    return title[:400]


async def upsert(
    db: AsyncSession,
    drafts: list[Draft],
    catalog: list[CatalogEntry],
) -> dict[str, int]:
    existing = {
        (row.platform, row.external_id): row
        for row in (await db.execute(select(Content))).scalars()
    }
    linked = {
        (link.content_id, link.concept_id)
        for link in (await db.execute(select(ContentConcept))).scalars()
    }
    created = 0
    updated = 0
    linked_n = 0
    skipped = 0

    for draft in drafts:
        if not draft.url or not draft.external_id:
            skipped += 1
            continue
        entry = best(draft, catalog)
        if entry is None:
            skipped += 1
            continue
        key = (draft.platform, draft.external_id[:128])
        row = existing.get(key)
        if row is None:
            row = Content(platform=draft.platform, external_id=draft.external_id[:128])
            db.add(row)
            existing[key] = row
            created += 1
        else:
            updated += 1
        row.title = _english_title(draft, entry)
        row.description = (draft.description or "")[:4000]
        row.creator = (draft.creator or draft.platform)[:120]
        row.url = draft.url[:1024]
        row.thumbnail_url = (draft.thumbnail_url or "")[:1024] or None
        row.thumbnail_ratio = draft.thumbnail_ratio or 0.75
        row.media_kind = draft.media_kind
        row.language = "en" if not _looks_cjk(draft.title) else draft.language
        row.duration_seconds = draft.duration_seconds
        row.subject_id = entry.subject_id
        row.topic = entry.concept.name
        row.tags = [entry.concept.slug, draft.platform, draft.media_kind]
        row.likes = max(0, draft.likes)
        row.comments = max(0, draft.comments)
        row.quality = _quality(draft)
        row.difficulty = entry.concept.difficulty
        row.is_sample = False
        row.published_at = draft.published_at
        extra = dict(draft.extra)
        extra["original_title"] = draft.title
        extra["ingested_at"] = datetime.now(UTC).isoformat()
        row.extra = extra
        await db.flush()
        pair = (row.id, entry.concept.id)
        if pair not in linked:
            db.add(
                ContentConcept(
                    content_id=row.id, concept_id=entry.concept.id, relevance=1.0
                )
            )
            linked.add(pair)
            linked_n += 1

    return {
        "created": created,
        "updated": updated,
        "linked": linked_n,
        "skipped": skipped,
    }


async def upsert_discussions(
    db: AsyncSession,
    drafts: list[Draft],
    catalog: list[CatalogEntry],
) -> int:
    existing = {
        row.external_id: row for row in (await db.execute(select(Discussion))).scalars()
    }
    with_comments = set(
        (await db.execute(select(DiscussionComment.discussion_id).distinct())).scalars()
    )
    created = 0
    for draft in drafts:
        if draft.media_kind not in {"discussion", "post"}:
            continue
        entry = best(draft, catalog)
        if entry is None:
            continue
        ext = draft.external_id[:128]
        row = existing.get(ext)
        if row is None:
            row = Discussion(external_id=ext)
            db.add(row)
            existing[ext] = row
            created += 1
        row.platform = draft.platform
        row.community = draft.community or draft.creator
        row.title = _english_title(draft, entry)
        row.body = (draft.description or "")[:8000]
        row.author = (draft.creator or "")[:120]
        row.url = draft.url
        row.language = draft.language
        row.upvotes = draft.likes
        row.comment_count = draft.comments
        row.concept_id = entry.concept.id
        row.is_sample = False
        await db.flush()
        if row.id not in with_comments:
            with_comments.add(row.id)
    return created


async def retire_samples(db: AsyncSession, *, min_real: int = 24) -> int:
    """Once real tutorials are in, the generated stand-ins leave.

    Discussion samples stay until real threads exist — otherwise Ask's
    translate/summarise paths have nothing to run against.
    """
    real = (
        await db.execute(
            select(func.count()).select_from(Content).where(Content.is_sample.is_(False))
        )
    ).scalar_one()
    if real < min_real:
        return 0
    result = await db.execute(delete(Content).where(Content.is_sample.is_(True)))
    real_disc = (
        await db.execute(
            select(func.count()).select_from(Discussion).where(Discussion.is_sample.is_(False))
        )
    ).scalar_one()
    if real_disc and real_disc >= 8:
        await db.execute(delete(Discussion).where(Discussion.is_sample.is_(True)))
    return result.rowcount or 0
