"""Reddit tutorials and explanations.

Public JSON search, no key. Subreddits are picked from the catalog subject so
a calculus query does not land in /r/AskHistorians.
"""

from __future__ import annotations

import asyncio
import re
from datetime import UTC, datetime

import httpx

from novi.core.logging import get_logger
from novi.services.ingest.draft import Draft
from novi.services.ingest.http import client

logger = get_logger(__name__)

# subject slug -> subreddits that actually teach that subject.
SUBREDDITS: dict[str, tuple[str, ...]] = {
    "mathematics": ("learnmath", "calculus", "math", "APStudents"),
    "physics": ("AskPhysics", "PhysicsStudents", "Physics"),
    "chemistry": ("chemhelp", "chemistry", "OrganicChemistry"),
    "biology": ("AskBiology", "biology", "APBio"),
    "computer-science": ("learnprogramming", "csmajors", "algorithms", "learnpython"),
    "history": ("AskHistorians", "history"),
    "economics": ("AskEconomics", "economics"),
    "psychology": ("askpsychology", "psychology"),
    "english": ("literature", "AskLiteraryStudies"),
    "earth-science": ("askscience", "geology"),
}

PULLPUSH = "https://api.pullpush.io/reddit/search/submission/"
DEFAULT_SUBS = ("explainlikeimfive", "AskAcademia", "HomeworkHelp")

_HTML = re.compile(r"<[^>]+>")


def _clean(text: str) -> str:
    return _HTML.sub("", text or "").replace("&amp;", "&").strip()


def parse_listing(payload: dict, *, query: str) -> list[Draft]:
    children = ((payload.get("data") or {}).get("children")) or []
    drafts: list[Draft] = []
    for child in children:
        data = child.get("data") or {}
        if data.get("over_18") or data.get("stickied"):
            continue
        post_id = data.get("id")
        title = _clean(data.get("title") or "")
        if not post_id or not title:
            continue
        permalink = data.get("permalink") or f"/comments/{post_id}"
        body = _clean(data.get("selftext") or "")[:800]
        thumb = data.get("thumbnail") or ""
        if thumb in {"self", "default", "nsfw", "spoiler", ""}:
            thumb = None
        elif not str(thumb).startswith("http"):
            thumb = None
        created = data.get("created_utc")
        published = None
        if isinstance(created, (int, float)):
            published = datetime.fromtimestamp(created, tz=UTC)
        drafts.append(
            Draft(
                platform="reddit",
                external_id=str(post_id),
                title=title[:400],
                description=body or f"Reddit discussion of {query}",
                creator=str(data.get("author") or "reddit")[:120],
                url=f"https://www.reddit.com{permalink}",
                media_kind="discussion",
                language="en",
                likes=int(data.get("ups") or 0),
                comments=int(data.get("num_comments") or 0),
                thumbnail_url=thumb,
                thumbnail_ratio=1.0,
                published_at=published,
                community=str(data.get("subreddit") or ""),
            )
        )
    return drafts


def subreddits_for(subject_slug: str) -> tuple[str, ...]:
    return SUBREDDITS.get(subject_slug, DEFAULT_SUBS)


async def _search(
    http: httpx.AsyncClient, query: str, subreddit: str | None
) -> list[Draft]:
    if subreddit:
        url = f"https://www.reddit.com/r/{subreddit}/search.json"
        params = {
            "q": query,
            "restrict_sr": "1",
            "sort": "relevance",
            "t": "year",
            "limit": "8",
        }
    else:
        url = "https://www.reddit.com/search.json"
        params = {
            "q": f"{query} tutorial OR explained",
            "sort": "relevance",
            "t": "year",
            "limit": "8",
        }
    return await _get_listing(http, url, params, query)


async def _hot(http: httpx.AsyncClient, subreddit: str) -> list[Draft]:
    url = f"https://www.reddit.com/r/{subreddit}/hot.json"
    return await _get_listing(http, url, {"limit": "25", "raw_json": "1"}, subreddit)


async def _get_listing(
    http: httpx.AsyncClient, url: str, params: dict, query: str
) -> list[Draft]:
    try:
        response = await http.get(url, params=params)
        if response.status_code >= 400:
            logger.warning(
                "reddit_search_failed",
                extra={"url": url, "status": response.status_code},
            )
            return []
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning(
            "reddit_search_failed",
            extra={"url": url, "error": type(exc).__name__},
        )
        return []
    if not isinstance(payload, dict):
        return []
    return parse_listing(payload, query=query)


async def _pullpush(
    http: httpx.AsyncClient, query: str, subreddit: str | None
) -> list[Draft]:
    """Public archive of real Reddit submissions.

    reddit.com itself is TLS-intercepted on some networks (Fortinet presents
    its own issuer for *.reddit.com). Pullpush returns the same posts with
    working reddit.com permalinks, so the feed still opens the original thread.
    """
    params: dict[str, str] = {
        "q": query,
        "size": "25",
        "sort": "desc",
        "sort_type": "score",
    }
    if subreddit:
        params["subreddit"] = subreddit
    try:
        response = await http.get(PULLPUSH, params=params)
        if response.status_code >= 400:
            logger.warning(
                "reddit_pullpush_failed", extra={"status": response.status_code}
            )
            return []
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("reddit_pullpush_failed", extra={"error": type(exc).__name__})
        return []
    rows = payload.get("data") if isinstance(payload, dict) else payload
    if not isinstance(rows, list):
        return []
    wrapped = {
        "data": {
            "children": [{"data": row} for row in rows if isinstance(row, dict)]
        }
    }
    return parse_listing(wrapped, query=query)


async def fetch(queries: list[str], *, subject_slugs: list[str] | None = None) -> list[Draft]:
    seen: set[str] = set()
    out: list[Draft] = []
    subs: list[str] = []
    for slug in subject_slugs or []:
        for name in subreddits_for(slug):
            if name not in subs:
                subs.append(name)
    if not subs:
        subs = list(DEFAULT_SUBS)

    headers = {
        "User-Agent": (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        ),
        "Accept": "application/json",
    }
    async with client(timeout=20.0) as http:
        http.headers.update(headers)
        jobs = [_hot(http, sub) for sub in subs[:10]]
        jobs += [_search(http, f"{q} explained OR tutorial", None) for q in queries[:8]]
        for batch in await asyncio.gather(*jobs):
            for draft in batch:
                if draft.external_id in seen:
                    continue
                seen.add(draft.external_id)
                out.append(draft)
        if not out:
            fallback = [_pullpush(http, f"{q} tutorial", None) for q in queries[:8]]
            fallback += [_pullpush(http, queries[0], sub) for sub in subs[:8] if queries]
            for batch in await asyncio.gather(*fallback):
                for draft in batch:
                    if draft.external_id in seen:
                        continue
                    seen.add(draft.external_id)
                    out.append(draft)
    logger.info("reddit_ingested", extra={"count": len(out)})
    return out
