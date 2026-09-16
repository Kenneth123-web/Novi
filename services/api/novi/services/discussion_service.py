"""Turning a community thread into something to learn from.

Both operations are cached on the row. Translation and summarisation are the
two most expensive calls in the product and neither changes once the thread is
fetched, so paying for them twice would be paying twice for the same bytes.
"""

from __future__ import annotations

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from novi.ai.gateway import gateway
from novi.ai.prompts import discussion as prompt
from novi.core.errors import NotFound
from novi.core.lang import language_key
from novi.core.logging import get_logger
from novi.models import Discussion

logger = get_logger(__name__)


async def _load(db: AsyncSession, discussion_id: uuid.UUID) -> Discussion:
    row = await db.get(Discussion, discussion_id)
    if row is None:
        raise NotFound("Discussion not found")
    return row


async def summarize(db: AsyncSession, discussion_id: uuid.UUID, *, force: bool = False) -> dict:
    row = await _load(db, discussion_id)
    if row.summary and not force:
        return row.summary

    result = await gateway.complete_json(
        system=prompt.SUMMARY_SYSTEM,
        user=prompt.build_summary_prompt(
            title=row.title,
            body=row.body,
            comments=[c.body for c in row.comments_],
        ),
        required_keys=prompt.SUMMARY_REQUIRED,
        temperature=0.3,
    )
    payload = {
        "main_ideas": result.data.get("main_ideas") or [],
        "agreement": result.data.get("agreement") or [],
        "disagreement": result.data.get("disagreement") or [],
        "common_mistakes": result.data.get("common_mistakes") or [],
        "useful_resources": result.data.get("useful_resources") or [],
        "model": result.model,
        "prompt_version": prompt.VERSION,
    }
    row.summary = payload
    await db.flush()
    return payload


async def translate(
    db: AsyncSession, discussion_id: uuid.UUID, *, target_language: str, force: bool = False
) -> dict:
    row = await _load(db, discussion_id)
    cached = row.translation or {}
    target_key = language_key(target_language)
    cached_key = language_key(cached.get("language") if isinstance(cached, dict) else None)
    if cached_key and cached_key == target_key and not force:
        return cached

    if language_key(row.language) == target_key:
        # Nothing to do, and saying so is better than paying a model to return
        # the input unchanged. `en` and `English` are the same language.
        return {"language": target_language, "unchanged": True}

    comments = [c.body for c in row.comments_]
    result = await gateway.complete_json(
        system=prompt.TRANSLATE_SYSTEM,
        user=prompt.build_translate_prompt(
            title=row.title, body=row.body, comments=comments, target_language=target_language
        ),
        required_keys=prompt.TRANSLATE_REQUIRED,
        temperature=0.2,
    )

    translated = result.data.get("comments")
    if not isinstance(translated, list) or len(translated) != len(comments):
        # A mismatched length means the comments can no longer be paired with
        # their originals. Showing them anyway would attribute one person's
        # words to another, so the body is kept and the comments are not.
        logger.warning(
            "translation_comment_count_mismatch",
            extra={"expected": len(comments), "got": len(translated or [])},
        )
        translated = []

    payload = {
        "language": target_language,
        "title": result.data.get("title") or row.title,
        "body": result.data.get("body") or "",
        "comments": translated,
        "model": result.model,
        "prompt_version": prompt.VERSION,
    }
    row.translation = payload
    await db.flush()
    return payload
