"""X (Twitter) educational posts.

Uses the official recent-search API when `X_BEARER_TOKEN` is set. Without a
token this source is a no-op — inventing tweets would be a fake record about
a real account.
"""

from __future__ import annotations

from datetime import UTC, datetime

import httpx

from novi.config import get_settings
from novi.core.logging import get_logger
from novi.services.ingest.draft import Draft
from novi.services.ingest.http import client

logger = get_logger(__name__)

SEARCH = "https://api.twitter.com/2/tweets/search/recent"


def parse_search(payload: dict) -> list[Draft]:
    users = {
        u.get("id"): u
        for u in ((payload.get("includes") or {}).get("users") or [])
        if u.get("id")
    }
    drafts: list[Draft] = []
    for tweet in payload.get("data") or []:
        tweet_id = tweet.get("id")
        text = (tweet.get("text") or "").strip()
        if not tweet_id or not text:
            continue
        author = users.get(tweet.get("author_id")) or {}
        handle = author.get("username") or "x"
        metrics = tweet.get("public_metrics") or {}
        created = tweet.get("created_at")
        published = None
        if created:
            try:
                published = datetime.fromisoformat(created.replace("Z", "+00:00"))
            except ValueError:
                published = datetime.now(UTC)
        drafts.append(
            Draft(
                platform="x",
                external_id=str(tweet_id),
                title=text.split("\n")[0][:180],
                description=text[:800],
                creator=str(handle)[:120],
                url=f"https://x.com/{handle}/status/{tweet_id}",
                media_kind="post",
                language="en",
                likes=int(metrics.get("like_count") or 0),
                comments=int(metrics.get("reply_count") or 0),
                thumbnail_ratio=1.2,
                published_at=published,
            )
        )
    return drafts


async def _search(http: httpx.AsyncClient, query: str, token: str) -> list[Draft]:
    q = f"({query} tutorial OR {query} explained) -is:retweet lang:en"
    try:
        response = await http.get(
            SEARCH,
            params={
                "query": q,
                "max_results": "10",
                "tweet.fields": "created_at,public_metrics,lang",
                "expansions": "author_id",
                "user.fields": "username,name",
            },
            headers={"Authorization": f"Bearer {token}"},
        )
        if response.status_code == 401:
            logger.warning("x_unauthorized")
            return []
        response.raise_for_status()
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("x_search_failed", extra={"error": type(exc).__name__})
        return []
    if not isinstance(payload, dict):
        return []
    return parse_search(payload)


async def fetch(queries: list[str]) -> list[Draft]:
    token = get_settings().x_bearer_token
    if not token:
        logger.info("x_skipped", extra={"reason": "no_bearer_token"})
        return []
    seen: set[str] = set()
    out: list[Draft] = []
    async with client() as http:
        for query in queries[:12]:
            for draft in await _search(http, query, token):
                if draft.external_id in seen:
                    continue
                seen.add(draft.external_id)
                out.append(draft)
    logger.info("x_ingested", extra={"count": len(out)})
    return out
