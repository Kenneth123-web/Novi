"""Within-subject areas the learner actually picks.

A subject slug is too coarse to rank from. Biology is cells, genetics,
physiology and ecology; those are different feeds. The catalog below is the
single source for onboarding chips, profile validation, ranking and the
passport. Every concept in `database.seeds.catalog.CONCEPTS` belongs to
exactly one area of its subject.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Area:
    slug: str
    name: str
    blurb: str
    concept_slugs: tuple[str, ...]


@dataclass(frozen=True)
class SubjectAreas:
    subject_slug: str
    subject_name: str
    areas: tuple[Area, ...]


def _area(slug: str, name: str, blurb: str, *concepts: str) -> Area:
    return Area(slug=slug, name=name, blurb=blurb, concept_slugs=concepts)


SUBJECT_AREAS: tuple[SubjectAreas, ...] = (
    SubjectAreas(
        "mathematics",
        "Mathematics",
        (
            _area(
                "algebra",
                "Algebra",
                "Equations, functions and the language of symbols.",
                "variables-expressions",
                "linear-equations",
                "quadratic-equations",
                "functions",
                "polynomials",
                "exponentials-logarithms",
            ),
            _area(
                "geometry",
                "Geometry & trig",
                "Shape, space and trigonometric ratios.",
                "trigonometric-ratios",
                "vectors",
            ),
            _area(
                "calculus",
                "Calculus",
                "Limits, rates of change and accumulation.",
                "sequences-series",
                "limits",
                "derivatives",
                "chain-rule",
                "integrals",
                "differential-equations",
            ),
            _area(
                "statistics",
                "Statistics & probability",
                "Chance, distributions and inference.",
                "probability",
                "distributions",
                "hypothesis-testing",
                "bayes-theorem",
            ),
            _area(
                "linear-algebra",
                "Linear algebra",
                "Matrices, vectors in coordinates, eigenvalues.",
                "matrices",
                "eigenvalues",
            ),
        ),
    ),
    SubjectAreas(
        "physics",
        "Physics",
        (
            _area(
                "mechanics",
                "Mechanics",
                "Motion, forces, energy and gravity.",
                "units-measurement",
                "kinematics",
                "newtons-laws",
                "momentum",
                "work-energy",
                "circular-motion",
                "gravitation",
            ),
            _area(
                "waves-optics",
                "Waves & optics",
                "Oscillations, light and images.",
                "waves",
                "optics",
            ),
            _area(
                "electricity",
                "Electricity & magnetism",
                "Fields, circuits and magnetic effects.",
                "electric-fields",
                "current-resistance",
                "ohms-law",
                "magnetism",
            ),
            _area(
                "thermodynamics",
                "Thermodynamics",
                "Heat, entropy and the laws that bind them.",
                "thermodynamics-laws",
                "entropy",
            ),
            _area(
                "modern",
                "Modern physics",
                "Relativity and the quantum scale.",
                "special-relativity",
                "quantum-basics",
            ),
        ),
    ),
    SubjectAreas(
        "chemistry",
        "Chemistry",
        (
            _area(
                "structure",
                "Structure & bonding",
                "Atoms, the periodic table and how atoms stick.",
                "atomic-structure",
                "periodic-trends",
                "chemical-bonding",
                "moles-stoichiometry",
            ),
            _area(
                "reactions",
                "Reactions & energy",
                "What happens, how fast, and how far.",
                "reaction-types",
                "acids-bases",
                "equilibrium",
                "thermochemistry",
                "reaction-kinetics",
                "electrochemistry",
            ),
            _area(
                "organic",
                "Organic chemistry",
                "Carbon skeletons, groups and mechanisms.",
                "organic-functional-groups",
                "reaction-mechanisms",
            ),
        ),
    ),
    SubjectAreas(
        "biology",
        "Biology",
        (
            _area(
                "cells",
                "Cells & energy",
                "What a cell is, and how it powers itself.",
                "cell-structure",
                "cell-transport",
                "photosynthesis",
                "cellular-respiration",
            ),
            _area(
                "genetics",
                "Genetics",
                "DNA, inheritance and protein-making.",
                "mitosis-meiosis",
                "dna-replication",
                "protein-synthesis",
                "mendelian-genetics",
            ),
            _area(
                "physiology",
                "Physiology",
                "How organisms keep themselves running.",
                "homeostasis",
                "nervous-system",
                "immune-system",
            ),
            _area(
                "ecology",
                "Evolution & ecology",
                "Populations, selection and ecosystems.",
                "natural-selection",
                "ecosystems",
            ),
        ),
    ),
    SubjectAreas(
        "computer-science",
        "Computer Science",
        (
            _area(
                "programming",
                "Programming",
                "The constructs you write code with.",
                "variables-types",
                "control-flow",
                "functions-scope",
                "arrays-lists",
                "hash-maps",
                "version-control",
            ),
            _area(
                "algorithms",
                "Algorithms",
                "Complexity, data structures and problem-solving.",
                "recursion",
                "big-o",
                "sorting-algorithms",
                "trees-graphs",
                "dynamic-programming",
            ),
            _area(
                "systems",
                "Systems",
                "How software talks to data and the network.",
                "databases-sql",
                "http-apis",
            ),
            _area(
                "ai-ml",
                "AI & machine learning",
                "Networks, embeddings and recommenders.",
                "neural-networks",
                "backpropagation",
                "embeddings",
                "recommendation-systems",
            ),
        ),
    ),
    SubjectAreas(
        "economics",
        "Economics",
        (
            _area(
                "micro",
                "Microeconomics",
                "Choices, markets and strategic behaviour.",
                "scarcity-tradeoffs",
                "supply-demand",
                "elasticity",
                "market-structures",
                "game-theory-basics",
            ),
            _area(
                "macro",
                "Macroeconomics",
                "The whole economy: output, prices, policy.",
                "gdp",
                "inflation",
                "monetary-policy",
                "comparative-advantage",
            ),
        ),
    ),
    SubjectAreas(
        "history",
        "History",
        (
            _area(
                "methods",
                "Historical method",
                "Sources, and the arguments historians have about them.",
                "primary-sources",
                "historiography",
            ),
            _area(
                "revolutions",
                "Revolutions",
                "Industrial and political ruptures.",
                "industrial-revolution",
                "french-revolution",
            ),
            _area(
                "twentieth-century",
                "The twentieth century",
                "World wars, the Cold War and decolonisation.",
                "world-war-one",
                "world-war-two",
                "cold-war",
                "decolonisation",
            ),
        ),
    ),
    SubjectAreas(
        "geography",
        "Geography",
        (
            _area(
                "physical",
                "Physical geography",
                "Earth systems: rock, water, weather.",
                "plate-tectonics",
                "weather-climate",
                "water-cycle",
            ),
            _area(
                "human",
                "Human geography",
                "People, cities and a changing climate.",
                "urbanisation",
                "population-models",
                "climate-change",
            ),
        ),
    ),
    SubjectAreas(
        "psychology",
        "Psychology",
        (
            _area(
                "methods",
                "Research methods",
                "How psychologists actually find things out.",
                "research-methods",
            ),
            _area(
                "cognition",
                "Cognition",
                "Memory and the shortcuts minds take.",
                "memory-models",
                "cognitive-biases",
            ),
            _area(
                "learning",
                "Learning",
                "Conditioning and how behaviour changes.",
                "classical-conditioning",
                "operant-conditioning",
            ),
            _area(
                "development",
                "Mind & body",
                "Attachment and the stress response.",
                "attachment",
                "stress-response",
            ),
        ),
    ),
    SubjectAreas(
        "languages",
        "Languages",
        (
            _area(
                "grammar",
                "Grammar",
                "Word order, tense and conditionals.",
                "word-order",
                "verb-tenses",
                "conditionals",
            ),
            _area(
                "usage",
                "Usage",
                "Collocations and the right register.",
                "collocations",
                "register-tone",
            ),
        ),
    ),
    SubjectAreas(
        "literature",
        "Literature",
        (
            _area(
                "reading",
                "Close reading",
                "Voice, image and what a text is doing.",
                "close-reading",
                "narrative-perspective",
                "metaphor-imagery",
            ),
            _area(
                "writing",
                "Writing about texts",
                "A thesis, then an essay that holds.",
                "thesis-statements",
                "essay-structure",
            ),
        ),
    ),
    SubjectAreas(
        "art",
        "Art & Design",
        (
            _area(
                "studio",
                "Studio practice",
                "Composition, colour and drawing in space.",
                "composition",
                "colour-theory",
                "perspective-drawing",
            ),
            _area(
                "design",
                "Design",
                "Type, and how to talk about visual work.",
                "typography-basics",
                "design-critique",
            ),
        ),
    ),
    SubjectAreas(
        "business",
        "Business",
        (
            _area(
                "strategy",
                "Strategy & marketing",
                "How a firm is built and how it finds customers.",
                "business-models",
                "marketing-funnels",
            ),
            _area(
                "finance",
                "Finance",
                "Unit economics and the statements behind them.",
                "unit-economics",
                "financial-statements",
            ),
        ),
    ),
    SubjectAreas(
        "engineering",
        "Engineering",
        (
            _area(
                "mechanics",
                "Mechanics",
                "Forces in real objects, and what they do to materials.",
                "free-body-diagrams",
                "stress-strain",
            ),
            _area(
                "electrical",
                "Electrical systems",
                "Circuits and the loops that control them.",
                "circuits",
                "control-systems",
            ),
            _area(
                "design",
                "Design & CAD",
                "Drawing the thing before you build it.",
                "cad-basics",
            ),
        ),
    ),
)

_BY_SUBJECT: dict[str, SubjectAreas] = {
    item.subject_slug: item for item in SUBJECT_AREAS
}
_AREA_BY_SUBJECT: dict[str, dict[str, Area]] = {
    item.subject_slug: {area.slug: area for area in item.areas} for item in SUBJECT_AREAS
}
_CONCEPT_AREA: dict[tuple[str, str], str] = {
    (item.subject_slug, concept): area.slug
    for item in SUBJECT_AREAS
    for area in item.areas
    for concept in area.concept_slugs
}


def subject_areas(slug: str) -> SubjectAreas | None:
    return _BY_SUBJECT.get(slug)


def area_slugs(subject_slug: str) -> set[str]:
    catalog = _BY_SUBJECT.get(subject_slug)
    return {area.slug for area in catalog.areas} if catalog else set()


def area_for_concept(subject_slug: str, concept_slug: str) -> str | None:
    return _CONCEPT_AREA.get((subject_slug, concept_slug))


def area_name(subject_slug: str, area_slug: str) -> str:
    area = _AREA_BY_SUBJECT.get(subject_slug, {}).get(area_slug)
    return area.name if area else area_slug.replace("-", " ").title()


def concepts_for_areas(subject_slug: str, area_slugs_: list[str]) -> set[str]:
    wanted = set(area_slugs_)
    catalog = _BY_SUBJECT.get(subject_slug)
    if catalog is None:
        return set()
    return {
        concept
        for area in catalog.areas
        if area.slug in wanted
        for concept in area.concept_slugs
    }


def area_as_dict(area: Area) -> dict:
    return {
        "slug": area.slug,
        "name": area.name,
        "blurb": area.blurb,
        "concept_slugs": list(area.concept_slugs),
    }


def subject_as_dict(item: SubjectAreas) -> dict:
    return {
        "subject_slug": item.subject_slug,
        "subject_name": item.subject_name,
        "areas": [area_as_dict(area) for area in item.areas],
    }


def all_subjects_payload() -> list[dict]:
    return [subject_as_dict(item) for item in SUBJECT_AREAS]


def areas_by_subject_payload() -> dict[str, list[dict]]:
    return {
        item.subject_slug: [area_as_dict(area) for area in item.areas]
        for item in SUBJECT_AREAS
    }
