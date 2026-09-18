"""Subject-area catalog integrity.

Every seeded concept must belong to exactly one area of its subject, or the
onboarding chips and the ranker silently disagree.
"""

from __future__ import annotations

import os
import sys

from novi.areas import SUBJECT_AREAS, area_for_concept, area_slugs, subject_areas

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def test_every_seeded_concept_has_exactly_one_area() -> None:
    if REPO_ROOT not in sys.path:
        sys.path.insert(0, REPO_ROOT)
    from database.seeds.catalog import CONCEPTS, SUBJECTS

    assert {item.subject_slug for item in SUBJECT_AREAS} == {
        subject["slug"] for subject in SUBJECTS
    }

    for subject_slug, concepts in CONCEPTS.items():
        catalog = subject_areas(subject_slug)
        assert catalog is not None, subject_slug
        claimed: dict[str, str] = {}
        for area in catalog.areas:
            assert area.concept_slugs, area.slug
            for concept in area.concept_slugs:
                assert concept not in claimed, (subject_slug, concept, area.slug, claimed[concept])
                claimed[concept] = area.slug
        seeded = {slug for slug, _, _ in concepts}
        assert set(claimed) == seeded, (
            subject_slug,
            sorted(seeded - set(claimed)),
            sorted(set(claimed) - seeded),
        )
        for slug, _, _ in concepts:
            assert area_for_concept(subject_slug, slug) in area_slugs(subject_slug)
