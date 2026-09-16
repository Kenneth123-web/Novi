"""Language tags the ranker and the translator both have to agree on.

The store uses short codes (`en`, `zh`). The iOS client asks to translate
to `English`. Treating those as different languages sends every English
thread through the model for a 140s no-op.
"""

from __future__ import annotations

_ALIASES = {
    "en": "en",
    "eng": "en",
    "english": "en",
    "zh": "zh",
    "chi": "zh",
    "chinese": "zh",
    "中文": "zh",
}


def language_key(value: str | None) -> str:
    raw = (value or "").strip().lower().replace("_", "-")
    if not raw:
        return ""
    if raw in _ALIASES:
        return _ALIASES[raw]
    prefix = raw.split("-", 1)[0]
    return _ALIASES.get(prefix, prefix[:8])
