"""Language matching for the English-only feed."""

from __future__ import annotations

from novi.core.lang import contains_non_latin, content_matches_language, language_key


def test_english_rejects_cjk_even_when_tagged_en() -> None:
    assert language_key("English") == "en"
    assert content_matches_language("en", "Derivatives in 3 minutes", "", "en")
    assert not content_matches_language("zh", "Derivatives in 3 minutes", "", "en")
    assert not content_matches_language("en", "导数超详细讲解", "高中数学", "en")
    assert contains_non_latin("导数")
    assert not contains_non_latin("The chain rule")
