"""Match a fetched title to a catalog concept.

A miss is dropped, not forced onto a random concept: a baking video in the
calculus column is worse than a slightly thinner feed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from novi.models import Concept
from novi.services.ingest.aliases import ZH_QUERIES
from novi.services.ingest.draft import Draft

_SPLIT = re.compile(r"[\s\-_/,:;()]+")
_GENERIC = {
    "the", "and", "for", "with", "from", "into", "that", "this", "your",
    "what", "how", "why", "law", "laws", "basics", "intro", "introduction",
    "explained", "tutorial", "lecture", "course", "part", "lesson",
}


@dataclass(frozen=True)
class CatalogEntry:
    concept: Concept
    subject_slug: str
    subject_id: object
    aliases: tuple[str, ...]


def build_catalog(
    concepts: list[Concept], subject_by_id: dict
) -> list[CatalogEntry]:
    out: list[CatalogEntry] = []
    for concept in concepts:
        subject = subject_by_id.get(concept.subject_id)
        if subject is None:
            continue
        aliases = tuple(ZH_QUERIES.get(concept.slug, ()))
        out.append(
            CatalogEntry(
                concept=concept,
                subject_slug=subject.slug,
                subject_id=subject.id,
                aliases=aliases,
            )
        )
    return out


def _tokens(text: str) -> set[str]:
    return {t for t in _SPLIT.split(text.lower()) if len(t) > 2 and t not in _GENERIC}


def score(draft: Draft, entry: CatalogEntry) -> float:
    hay = f"{draft.title} {draft.description} {draft.community}".lower()
    name = entry.concept.name.lower()
    if name and name in hay:
        return 3.0 + min(len(name), 40) / 20
    for alias in entry.aliases:
        if alias and alias.split()[0].lower() in hay:
            return 2.6
    slug_phrase = entry.concept.slug.replace("-", " ")
    if slug_phrase in hay:
        return 2.2
    words = [w for w in _tokens(name) if len(w) > 3]
    if words and all(w in hay for w in words):
        return 2.0
    if len(name) >= 10 and name in hay:
        return 2.4
    return 0.0


def best(draft: Draft, catalog: list[CatalogEntry]) -> CatalogEntry | None:
    ranked = [(score(draft, entry), entry) for entry in catalog]
    ranked.sort(key=lambda pair: pair[0], reverse=True)
    if not ranked or ranked[0][0] < 2.0:
        return None
    return ranked[0][1]
