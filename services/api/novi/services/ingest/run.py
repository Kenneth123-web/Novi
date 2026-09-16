"""Run every tutorial source, match to the catalog, store, retire samples.

    .venv/bin/python -m novi.services.ingest
"""

from __future__ import annotations

import asyncio
import sys

from sqlalchemy import select

from novi.core.logging import get_logger
from novi.db import dispose_engine, get_sessionmaker
from novi.models import Concept, Subject
from novi.services.ingest.match import build_catalog
from novi.services.ingest.sources import mediacrawler, reddit, x, youtube
from novi.services.ingest.store import retire_samples, upsert, upsert_discussions

logger = get_logger(__name__)


async def run() -> dict[str, object]:
    async with get_sessionmaker()() as db:
        concepts = list((await db.execute(select(Concept))).scalars())
        subjects = {s.id: s for s in (await db.execute(select(Subject))).scalars()}
        catalog = build_catalog(concepts, subjects)
        if not catalog:
            raise RuntimeError("catalog is empty — run ./scripts/dev.sh seed first")

        queries = [entry.concept.name for entry in catalog]
        subject_slugs = sorted({entry.subject_slug for entry in catalog})

        gathered = await asyncio.gather(
            youtube.fetch(queries),
            reddit.fetch(queries, subject_slugs=subject_slugs),
            x.fetch(queries),
            mediacrawler.fetch(catalog),
            return_exceptions=True,
        )
        names = ("youtube", "reddit", "x", "mediacrawler")
        fetched: dict[str, int] = {}
        drafts = []
        reddit_d: list = []
        x_d: list = []
        for name, result in zip(names, gathered, strict=True):
            if isinstance(result, Exception):
                logger.warning(
                    "ingest_source_failed",
                    extra={"source": name, "error": type(result).__name__},
                )
                fetched[name] = 0
                continue
            fetched[name] = len(result)
            drafts.extend(result)
            if name == "reddit":
                reddit_d = result
            elif name == "x":
                x_d = result
        stats = await upsert(db, drafts, catalog)
        discussions = await upsert_discussions(db, reddit_d + x_d, catalog)
        retired = await retire_samples(db)
        await db.commit()

        result = {
            "fetched": fetched,
            **stats,
            "discussions": discussions,
            "retired_samples": retired,
        }
        logger.info("ingest_finished", extra=result)
        return result


async def main() -> int:
    stats = await run()
    fetched = stats["fetched"]
    print(
        "ingest: fetched "
        + ", ".join(f"{v} {k}" for k, v in fetched.items())
        + f"; stored {stats['created']} new, {stats['updated']} updated, "
        + f"{stats['skipped']} unmatched; discussions {stats['discussions']}; "
        + f"retired {stats['retired_samples']} samples"
    )
    await dispose_engine()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
