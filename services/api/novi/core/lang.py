"""Language tags the ranker and the translator both have to agree on.

The store uses short codes (`en`, `zh`). The iOS client asks to translate
to `English`. Treating those as different languages sends every English
thread through the model for a 140s no-op.
"""

from __future__ import annotations

import re

from sqlalchemy import func, or_
from sqlalchemy.sql.elements import ColumnElement

_ALIASES = {
    "en": "en",
    "eng": "en",
    "english": "en",
    "zh": "zh",
    "chi": "zh",
    "chinese": "zh",
    "中文": "zh",
}

# Scripts that mean the item is not English, even if the language tag says so.
# The feed used to *prefer* English and still surface Bilibili/Zhihu cards.
_NON_LATIN = re.compile(
    r"[\u0400-\u04FF\u0600-\u06FF\u0900-\u097F\u0E00-\u0E7F"
    r"\u3040-\u30FF\u3400-\u9FFF\uAC00-\uD7AF\uF900-\uFAFF]"
)


def language_key(value: str | None) -> str:
    raw = (value or "").strip().lower().replace("_", "-")
    if not raw:
        return ""
    if raw in _ALIASES:
        return _ALIASES[raw]
    prefix = raw.split("-", 1)[0]
    return _ALIASES.get(prefix, prefix[:8])


def language_aliases(lang: str) -> tuple[str, ...]:
    wanted = language_key(lang)
    if wanted == "en":
        return ("en", "eng", "english")
    if wanted == "zh":
        return ("zh", "chi", "chinese", "中文", "zh-cn", "zh-tw", "zh-hans", "zh-hant")
    return (wanted,) if wanted else ()


def language_clause(column: ColumnElement[str], lang: str) -> ColumnElement[bool]:
    """SQL predicate: this row is tagged as `lang`, including regional variants."""
    wanted = language_key(lang) or lang
    aliases = language_aliases(wanted)
    clauses = [func.lower(column).in_(aliases)]
    if wanted:
        clauses.append(func.lower(column).like(f"{wanted}-%"))
    return or_(*clauses)


def contains_non_latin(text: str | None) -> bool:
    return bool(text and _NON_LATIN.search(text))


def content_matches_language(
    language: str | None, title: str, description: str, wanted: str
) -> bool:
    if language_key(language) != language_key(wanted):
        return False
    if language_key(wanted) == "en" and contains_non_latin(f"{title}\n{description}"):
        return False
    return True
