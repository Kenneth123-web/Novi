"""Tutorial ingest: parsers, matching, and storing real rows."""

from __future__ import annotations

from types import SimpleNamespace

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from novi.db import get_sessionmaker
from novi.models import Concept, Content, Subject
from novi.services.ingest.draft import Draft
from novi.services.ingest.match import CatalogEntry, best, score
from novi.services.ingest.sources.mediacrawler import (
    load_dump,
    parse_bilibili_search,
    parse_mediacrawler_row,
)
from novi.services.ingest.sources.reddit import parse_listing
from novi.services.ingest.sources.x import parse_search
from novi.services.ingest.sources.youtube import parse_atom
from novi.services.ingest.store import upsert

ATOM = """\
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:yt="http://www.youtube.com/xml/schemas/2015"
      xmlns:media="http://search.yahoo.com/mrss/">
  <entry>
    <yt:videoId>abcDeriv123</yt:videoId>
    <title>The essence of derivatives</title>
    <author><name>3Blue1Brown</name></author>
    <published>2024-01-02T00:00:00+00:00</published>
    <media:group>
      <media:description>A visual take on the derivative as slope.</media:description>
      <media:thumbnail url="https://i.ytimg.com/vi/abcDeriv123/hq.jpg" width="480" height="360"/>
    </media:group>
  </entry>
</feed>
"""


def test_youtube_atom_becomes_a_watch_url() -> None:
    drafts = parse_atom(ATOM, "3Blue1Brown")
    assert len(drafts) == 1
    d = drafts[0]
    assert d.platform == "youtube"
    assert d.external_id == "abcDeriv123"
    assert d.url == "https://www.youtube.com/watch?v=abcDeriv123"
    assert d.creator == "3Blue1Brown"
    assert "derivative" in d.title.lower()


def test_reddit_listing_skips_nsfw_and_builds_permalink() -> None:
    payload = {
        "data": {
            "children": [
                {
                    "data": {
                        "id": "nsfw1",
                        "title": "bad",
                        "over_18": True,
                        "permalink": "/r/x/comments/nsfw1/",
                    }
                },
                {
                    "data": {
                        "id": "abc123",
                        "title": "Can someone explain derivatives?",
                        "selftext": "I am stuck on the definition.",
                        "author": "learner",
                        "permalink": "/r/learnmath/comments/abc123/deriv/",
                        "ups": 42,
                        "num_comments": 7,
                        "subreddit": "learnmath",
                        "created_utc": 1_700_000_000,
                        "thumbnail": "self",
                    }
                },
            ]
        }
    }
    drafts = parse_listing(payload, query="derivatives")
    assert len(drafts) == 1
    d = drafts[0]
    assert d.platform == "reddit"
    assert d.url == "https://www.reddit.com/r/learnmath/comments/abc123/deriv/"
    assert d.likes == 42
    assert d.community == "learnmath"


def test_bilibili_search_strips_em_and_builds_watch_url() -> None:
    payload = {
        "code": 0,
        "data": {
            "result": [
                {
                    "type": "video",
                    "bvid": "BV1xx411c7mD",
                    "title": "<em class=\"keyword\">导数</em> 讲解 高中",
                    "description": "高中数学导数入门",
                    "author": "老师A",
                    "pic": "//i0.hdslb.com/bfs/cover/x.jpg",
                    "duration": "12:04",
                    "like": 900,
                    "pubdate": 1_700_000_000,
                }
            ]
        },
    }
    drafts = parse_bilibili_search(payload)
    assert len(drafts) == 1
    d = drafts[0]
    assert d.platform == "bilibili"
    assert d.title == "导数 讲解 高中"
    assert d.url == "https://www.bilibili.com/video/BV1xx411c7mD"
    assert d.thumbnail_url.startswith("https://")
    assert d.duration_seconds == 12 * 60 + 4


def test_mediacrawler_dump_row_from_xhs() -> None:
    draft = parse_mediacrawler_row(
        {
            "platform": "xhs",
            "note_id": "64abc",
            "title": "导数怎么学",
            "desc": "高中数学笔记",
            "nickname": "学霸",
            "liked_count": "1200",
            "note_url": "https://www.xiaohongshu.com/explore/64abc",
        }
    )
    assert draft is not None
    assert draft.platform == "xiaohongshu"
    assert draft.url.endswith("/64abc")


def test_x_search_builds_status_url() -> None:
    payload = {
        "data": [
            {
                "id": "123",
                "text": "Derivatives are just slope. Thread.",
                "author_id": "u1",
                "created_at": "2024-01-02T00:00:00.000Z",
                "public_metrics": {"like_count": 10, "reply_count": 2},
            }
        ],
        "includes": {"users": [{"id": "u1", "username": "mathperson"}]},
    }
    drafts = parse_search(payload)
    assert drafts[0].url == "https://x.com/mathperson/status/123"


def test_cjk_title_matches_chinese_alias() -> None:
    concept = SimpleNamespace(name="Derivatives", slug="derivatives")
    entry = CatalogEntry(
        concept=concept,  # type: ignore[arg-type]
        subject_slug="mathematics",
        subject_id="x",
        aliases=("导数 讲解 高中",),
    )
    draft = Draft(
        platform="bilibili",
        external_id="BV1",
        title="高中导数讲解全集",
        description="",
        creator="老师",
        url="https://www.bilibili.com/video/BV1",
    )
    assert score(draft, entry) >= 2.0
    assert best(draft, [entry]) is entry


async def test_upsert_stores_a_real_matched_tutorial(seeded: None) -> None:
    async with get_sessionmaker()() as db:
        catalog = await _catalog(db)
        stats = await upsert(
            db,
            [
                Draft(
                    platform="youtube",
                    external_id="realDeriv01",
                    title="Derivatives explained visually",
                    description="The slope of a curve at a point.",
                    creator="3Blue1Brown",
                    url="https://www.youtube.com/watch?v=realDeriv01",
                    media_kind="video",
                    likes=1000,
                )
            ],
            catalog,
        )
        await db.commit()
        assert stats["created"] == 1
        assert stats["skipped"] == 0
        row = (
            await db.execute(select(Content).where(Content.external_id == "realDeriv01"))
        ).scalar_one()
        assert row.is_sample is False
        assert row.url == "https://www.youtube.com/watch?v=realDeriv01"
        assert row.topic  # matched a catalog concept


async def test_unrelated_title_is_not_forced_onto_a_concept(seeded: None) -> None:
    async with get_sessionmaker()() as db:
        catalog = await _catalog(db)
        stats = await upsert(
            db,
            [
                Draft(
                    platform="youtube",
                    external_id="cake01",
                    title="How to bake a chocolate cake",
                    description="Preheat the oven.",
                    creator="Food",
                    url="https://www.youtube.com/watch?v=cake01",
                )
            ],
            catalog,
        )
        await db.commit()
        assert stats["created"] == 0
        assert stats["skipped"] == 1


async def _catalog(db: AsyncSession):
    from novi.services.ingest.match import build_catalog

    concepts = list((await db.execute(select(Concept))).scalars())
    subjects = {s.id: s for s in (await db.execute(select(Subject))).scalars()}
    return build_catalog(concepts, subjects)


def test_load_dump_jsonl(tmp_path) -> None:
    path = tmp_path / "bili.jsonl"
    path.write_text(
        '{"bvid":"BV1yy","title":"积分入门","nickname":"UP","desc":"微积分"}\n',
        encoding="utf-8",
    )
    drafts = load_dump(path)
    assert len(drafts) == 1
    assert drafts[0].platform == "bilibili"
    assert drafts[0].external_id == "BV1yy"
