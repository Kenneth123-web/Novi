"""Chinese-platform tutorials via MediaCrawler's sources.

Live path: Bilibili keyword search — the same public search MediaCrawler uses
for `--platform bili --type search`. Titles stay in the original language until
`store._english_title` (and the optional AI pass) leads with the catalog name.

Dump path: JSON/JSONL written by https://github.com/NanmiCoder/MediaCrawler
(Xiaohongshu, Douyin, Kuaishou, Weibo, Tieba, Zhihu, Bilibili). Cookie-gated
platforms cannot be searched from this process without Playwright login, so
those land here after a MediaCrawler run pointed at `MEDIACRAWLER_DATA_DIR`.
"""

from __future__ import annotations

import asyncio
import json
import re
from datetime import UTC, datetime
from pathlib import Path

import httpx

from novi.config import get_settings
from novi.core.logging import get_logger
from novi.services.ingest.aliases import queries_for
from novi.services.ingest.draft import Draft
from novi.services.ingest.http import client
from novi.services.ingest.match import CatalogEntry

logger = get_logger(__name__)

BILI_SEARCH = "https://api.bilibili.com/x/web-interface/search/type"
_HTML = re.compile(r"<[^>]+>")
_DURATION = re.compile(r"^(?:(\d+):)?(\d+):(\d+)$")

PLATFORM_ALIASES = {
    "bili": "bilibili",
    "bilibili": "bilibili",
    "xhs": "xiaohongshu",
    "xiaohongshu": "xiaohongshu",
    "dy": "douyin",
    "douyin": "douyin",
    "ks": "kuaishou",
    "kuaishou": "kuaishou",
    "wb": "weibo",
    "weibo": "weibo",
    "tieba": "tieba",
    "zhihu": "zhihu",
}


def _clean(text: str) -> str:
    return _HTML.sub("", (text or "").replace("&amp;", "&")).strip()


def _duration_seconds(raw: object) -> int | None:
    if isinstance(raw, (int, float)):
        value = int(raw)
        return value if value > 0 else None
    text = str(raw or "").strip()
    match = _DURATION.match(text)
    if not match:
        return None
    hours = int(match.group(1) or 0)
    minutes = int(match.group(2))
    seconds = int(match.group(3))
    return hours * 3600 + minutes * 60 + seconds


def _url(platform: str, external_id: str, fallback: str | None = None) -> str:
    if fallback and fallback.startswith("http"):
        return fallback
    if platform == "bilibili":
        return f"https://www.bilibili.com/video/{external_id}"
    if platform == "xiaohongshu":
        return f"https://www.xiaohongshu.com/explore/{external_id}"
    if platform == "douyin":
        return f"https://www.douyin.com/video/{external_id}"
    if platform == "zhihu":
        return f"https://www.zhihu.com/question/{external_id}"
    if platform == "weibo":
        return f"https://m.weibo.cn/detail/{external_id}"
    return fallback or ""


def parse_bilibili_search(payload: dict) -> list[Draft]:
    data = payload.get("data") or {}
    rows = data.get("result") or data.get("items") or []
    drafts: list[Draft] = []
    for item in rows:
        if not isinstance(item, dict):
            continue
        if item.get("type") not in (None, "video", "bili_video"):
            # The mixed search endpoint includes users and lives.
            if "bvid" not in item and "aid" not in item:
                continue
        bvid = item.get("bvid") or item.get("aid")
        title = _clean(item.get("title") or "")
        if not bvid or not title:
            continue
        bvid = str(bvid)
        pic = item.get("pic") or item.get("cover") or ""
        if isinstance(pic, str) and pic.startswith("//"):
            pic = "https:" + pic
        pubdate = item.get("pubdate") or item.get("created")
        published = None
        if isinstance(pubdate, (int, float)):
            published = datetime.fromtimestamp(int(pubdate), tz=UTC)
        drafts.append(
            Draft(
                platform="bilibili",
                external_id=bvid,
                title=title[:400],
                description=_clean(item.get("description") or item.get("desc") or "")[:800],
                creator=str(item.get("author") or item.get("uname") or "bilibili")[:120],
                url=_url("bilibili", bvid, item.get("arcurl") or item.get("video_url")),
                media_kind="video",
                language="zh",
                likes=int(item.get("like") or item.get("likes") or 0),
                comments=int(item.get("review") or item.get("video_review") or 0),
                duration_seconds=_duration_seconds(item.get("duration")),
                thumbnail_url=pic or None,
                thumbnail_ratio=1.33,
                published_at=published,
                extra={"play": item.get("play"), "source": "mediacrawler-bili-search"},
            )
        )
    return drafts


def parse_mediacrawler_row(row: dict) -> Draft | None:
    """One record from a MediaCrawler JSON/JSONL dump, any supported platform."""
    platform_raw = str(
        row.get("platform") or row.get("source") or row.get("source_keyword") or ""
    ).lower()
    platform = PLATFORM_ALIASES.get(platform_raw, "")
    if not platform:
        if row.get("bvid") or (row.get("video_url") or "").find("bilibili") >= 0:
            platform = "bilibili"
        elif row.get("note_id") or row.get("noteId"):
            platform = "xiaohongshu"
        elif row.get("aweme_id"):
            platform = "douyin"
        elif row.get("mblogid"):
            platform = "weibo"
        else:
            return None

    external_id = str(
        row.get("bvid")
        or row.get("video_id")
        or row.get("aweme_id")
        or row.get("note_id")
        or row.get("noteId")
        or row.get("mblogid")
        or row.get("video_id_str")
        or row.get("id")
        or ""
    )
    title = _clean(str(row.get("title") or row.get("desc") or row.get("content") or ""))
    if not external_id or not title:
        return None
    url = _url(
        platform,
        external_id,
        row.get("video_url") or row.get("note_url") or row.get("url") or row.get("aweme_url"),
    )
    if not url:
        return None
    likes = row.get("liked_count") or row.get("liked_count_str") or row.get("like_count") or 0
    try:
        likes = int(str(likes).replace(",", "").replace("万", "0000") or 0)
    except ValueError:
        likes = 0
    thumb = row.get("cover") or row.get("video_cover_url") or row.get("avatar") or row.get("pic")
    if isinstance(thumb, str) and thumb.startswith("//"):
        thumb = "https:" + thumb
    return Draft(
        platform=platform,
        external_id=external_id[:128],
        title=title[:400],
        description=_clean(str(row.get("desc") or row.get("ip_location") or ""))[:800],
        creator=str(
            row.get("nickname") or row.get("user_id") or row.get("author") or platform
        )[:120],
        url=url[:1024],
        media_kind="video" if platform in {"bilibili", "douyin", "kuaishou"} else "post",
        language="zh",
        likes=likes,
        comments=int(row.get("comment_count") or row.get("comments") or 0) or 0,
        thumbnail_url=thumb if isinstance(thumb, str) else None,
        thumbnail_ratio=0.75 if platform == "xiaohongshu" else 1.33,
        extra={"source": "mediacrawler-dump", "source_keyword": row.get("source_keyword")},
    )


def load_dump(path: Path) -> list[Draft]:
    drafts: list[Draft] = []
    if path.suffix.lower() == ".jsonl":
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(row, dict):
                draft = parse_mediacrawler_row(row)
                if draft:
                    drafts.append(draft)
        return drafts
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    rows: list[dict]
    if isinstance(payload, list):
        rows = [r for r in payload if isinstance(r, dict)]
    elif isinstance(payload, dict):
        inner = payload.get("data") or payload.get("contents") or payload.get("items")
        if isinstance(inner, list):
            rows = [r for r in inner if isinstance(r, dict)]
        else:
            rows = [payload]
    else:
        return []
    for row in rows:
        draft = parse_mediacrawler_row(row)
        if draft:
            drafts.append(draft)
    return drafts


def import_dump() -> list[Draft]:
    raw = get_settings().mediacrawler_data_dir
    if not raw:
        return []
    root = Path(raw).expanduser()
    if not root.is_dir():
        logger.warning("mediacrawler_dump_missing", extra={"path": raw})
        return []
    seen: set[tuple[str, str]] = set()
    out: list[Draft] = []
    for path in sorted(root.rglob("*")):
        if path.suffix.lower() not in {".json", ".jsonl"}:
            continue
        for draft in load_dump(path):
            key = (draft.platform, draft.external_id)
            if key in seen:
                continue
            seen.add(key)
            out.append(draft)
    logger.info("mediacrawler_dump_imported", extra={"count": len(out)})
    return out


async def _bilibili_search(http: httpx.AsyncClient, keyword: str) -> list[Draft]:
    try:
        response = await http.get(
            BILI_SEARCH,
            params={
                "search_type": "video",
                "keyword": keyword,
                "page": 1,
                "order": "totalrank",
            },
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
                ),
                "Referer": "https://search.bilibili.com",
                "Accept": "application/json, text/plain, */*",
            },
        )
        response.raise_for_status()
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        logger.warning("bilibili_search_failed", extra={"error": type(exc).__name__})
        return []
    if not isinstance(payload, dict) or payload.get("code") not in (0, None):
        logger.warning(
            "bilibili_search_rejected",
            extra={"code": payload.get("code") if isinstance(payload, dict) else None},
        )
        return []
    return parse_bilibili_search(payload)


async def fetch(catalog: list[CatalogEntry]) -> list[Draft]:
    """Search Bilibili with the Chinese aliases MediaCrawler would type."""
    seen: set[str] = set()
    out: list[Draft] = []
    queries: list[str] = []
    for entry in catalog:
        for q in queries_for(entry.concept.slug, entry.concept.name)[:1]:
            if q not in queries:
                queries.append(q)
    async with client(timeout=20.0) as http:
        batches = await asyncio.gather(
            *[_bilibili_search(http, keyword) for keyword in queries[:16]]
        )
        for batch in batches:
            for draft in batch:
                if draft.external_id in seen:
                    continue
                seen.add(draft.external_id)
                out.append(draft)
    dumped = import_dump()
    for draft in dumped:
        if draft.external_id in seen and draft.platform == "bilibili":
            continue
        seen.add(draft.external_id)
        out.append(draft)
    logger.info("mediacrawler_ingested", extra={"count": len(out)})
    return out
