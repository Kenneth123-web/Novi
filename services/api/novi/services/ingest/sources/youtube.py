"""YouTube tutorials: channel RSS plus optional Data API / Invidious search.

RSS needs no key and returns real watch URLs. The Data API is used when
`YOUTUBE_API_KEY` is set. Invidious is the unauthenticated search fallback.
"""

from __future__ import annotations

import asyncio
import xml.etree.ElementTree as ET
from datetime import UTC, datetime

import httpx

from novi.config import get_settings
from novi.core.logging import get_logger
from novi.services.ingest.draft import Draft
from novi.services.ingest.http import client

logger = get_logger(__name__)

ATOM = "{http://www.w3.org/2005/Atom}"
MEDIA = "{http://search.yahoo.com/mrss/}"
YT = "{http://www.youtube.com/xml/schemas/2015}"

# Educational channels whose uploads we match against the catalog.
CHANNELS: list[tuple[str, str]] = [
    ("UCYO_jab_esuFRV4b17AJtAw", "3Blue1Brown"),
    ("UC4a-Gbdw7vOaccHmFo40b9g", "Khan Academy"),
    ("UCHnyfMqiRRG1u-2MsSQLbXA", "Veritasium"),
    ("UCUHW94eEFW7hkUMVaZz4eDg", "minutephysics"),
    ("UCUepbWJqzAzqLNOjUpz-mgQ", "Amoeba Sisters"),
    ("UC9-y-6csu5WGm29I7JiwpnA", "Computerphile"),
    ("UCEBb1b_L6zDS3xTUrIALZOw", "MIT OpenCourseWare"),
    ("UCX6b17PVsYBQ0ip5gyeme-Q", "CrashCourse"),
    ("UCsooa4yRKGN_zEE8iknghZA", "TED-Ed"),
    ("UCoxcjq-8xIDTYp3uz647V5A", "Numberphile"),
    ("UC0UD2KSZESc5PCPzTBZC_dw", "Professor Dave Explains"),
    ("UCEWpbFLzoYGPfuWUMFPSaoA", "The Organic Chemistry Tutor"),
    ("UCvjgXvBlbQiydffZU7m1_aw", "The Coding Train"),
    ("UC2DjFE7Xf11URZqWBigcVOQ", "Engineering Explained"),
    ("UCBa659QWEk1AI4Tg--mrJ2A", "Tom Scott"),
]

INVIDIOUS = (
    "https://inv.nadeko.net",
    "https://invidious.nerdvpn.de",
    "https://yt.artemislena.eu",
)


def parse_atom(xml_text: str, fallback_creator: str) -> list[Draft]:
    root = ET.fromstring(xml_text)  # noqa: S314 — YouTube Atom, not untrusted XML
    drafts: list[Draft] = []
    for entry in root.findall(f"{ATOM}entry"):
        video_id = (entry.findtext(f"{YT}videoId") or "").strip()
        title = (entry.findtext(f"{ATOM}title") or "").strip()
        if not video_id or not title:
            continue
        author = entry.find(f"{ATOM}author")
        creator = (
            (author.findtext(f"{ATOM}name") if author is not None else None)
            or fallback_creator
        )
        published_raw = entry.findtext(f"{ATOM}published") or ""
        published_at = None
        if published_raw:
            try:
                published_at = datetime.fromisoformat(published_raw.replace("Z", "+00:00"))
            except ValueError:
                published_at = None
        media = entry.find(f"{MEDIA}group")
        description = ""
        thumb = None
        ratio = 1.33
        if media is not None:
            description = (media.findtext(f"{MEDIA}description") or "")[:800]
            thumb_el = media.find(f"{MEDIA}thumbnail")
            if thumb_el is not None:
                thumb = thumb_el.attrib.get("url")
                try:
                    w = float(thumb_el.attrib.get("width") or 0)
                    h = float(thumb_el.attrib.get("height") or 0)
                    if w and h:
                        ratio = round(w / h, 3)
                except ValueError:
                    pass
        drafts.append(
            Draft(
                platform="youtube",
                external_id=video_id,
                title=title,
                description=description,
                creator=creator[:120],
                url=f"https://www.youtube.com/watch?v={video_id}",
                media_kind="video",
                language="en",
                thumbnail_url=thumb,
                thumbnail_ratio=ratio,
                published_at=published_at or datetime.now(UTC),
            )
        )
    return drafts


async def _rss(http: httpx.AsyncClient, channel_id: str, name: str) -> list[Draft]:
    url = f"https://www.youtube.com/feeds/videos.xml?channel_id={channel_id}"
    try:
        response = await http.get(url)
        response.raise_for_status()
    except httpx.HTTPError as exc:
        logger.warning("youtube_rss_failed", extra={"channel": name, "error": type(exc).__name__})
        return []
    return parse_atom(response.text, name)


async def _data_api(http: httpx.AsyncClient, query: str, key: str) -> list[Draft]:
    url = "https://www.googleapis.com/youtube/v3/search"
    try:
        response = await http.get(
            url,
            params={
                "part": "snippet",
                "q": query,
                "type": "video",
                "maxResults": 5,
                "safeSearch": "strict",
                "key": key,
            },
        )
        response.raise_for_status()
        payload = response.json()
    except httpx.HTTPError as exc:
        logger.warning("youtube_api_failed", extra={"error": type(exc).__name__})
        return []
    drafts: list[Draft] = []
    for item in payload.get("items") or []:
        video_id = (item.get("id") or {}).get("videoId")
        snippet = item.get("snippet") or {}
        if not video_id or not snippet.get("title"):
            continue
        thumbs = snippet.get("thumbnails") or {}
        thumb = (thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {})
        drafts.append(
            Draft(
                platform="youtube",
                external_id=video_id,
                title=snippet["title"],
                description=(snippet.get("description") or "")[:800],
                creator=(snippet.get("channelTitle") or "YouTube")[:120],
                url=f"https://www.youtube.com/watch?v={video_id}",
                media_kind="video",
                language="en",
                thumbnail_url=thumb.get("url"),
                thumbnail_ratio=1.33,
            )
        )
    return drafts


async def _invidious(http: httpx.AsyncClient, query: str) -> list[Draft]:
    for base in INVIDIOUS:
        try:
            response = await http.get(
                f"{base}/api/v1/search",
                params={"q": query, "type": "video"},
            )
            if response.status_code >= 400:
                continue
            payload = response.json()
        except httpx.HTTPError:
            continue
        if not isinstance(payload, list):
            continue
        drafts: list[Draft] = []
        for item in payload[:6]:
            video_id = item.get("videoId")
            title = item.get("title")
            if not video_id or not title:
                continue
            drafts.append(
                Draft(
                    platform="youtube",
                    external_id=video_id,
                    title=title,
                    description=(item.get("description") or "")[:800],
                    creator=(item.get("author") or "YouTube")[:120],
                    url=f"https://www.youtube.com/watch?v={video_id}",
                    media_kind="video",
                    language="en",
                    likes=int(item.get("likeCount") or 0),
                    duration_seconds=int(item.get("lengthSeconds") or 0) or None,
                    thumbnail_ratio=1.33,
                )
            )
        if drafts:
            return drafts
    return []


async def _search(http: httpx.AsyncClient, query: str, key: str | None) -> list[Draft]:
    extra: list[Draft] = []
    if key:
        extra = await _data_api(http, f"{query} tutorial", key)
    if not extra:
        extra = await _invidious(http, f"{query} explained tutorial")
    return extra


async def fetch(queries: list[str]) -> list[Draft]:
    s = get_settings()
    seen: set[str] = set()
    out: list[Draft] = []
    async with client() as http:
        rss_lists = await asyncio.gather(
            *[_rss(http, channel_id, name) for channel_id, name in CHANNELS]
        )
        for drafts in rss_lists:
            for draft in drafts:
                if draft.external_id in seen:
                    continue
                seen.add(draft.external_id)
                out.append(draft)
        extra_lists = await asyncio.gather(
            *[_search(http, query, s.youtube_api_key) for query in queries[:16]]
        )
        for extra in extra_lists:
            for draft in extra:
                if draft.external_id in seen:
                    continue
                seen.add(draft.external_id)
                out.append(draft)
    logger.info("youtube_ingested", extra={"count": len(out)})
    return out
