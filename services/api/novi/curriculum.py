"""Deterministic grade curriculum used by customization and the passport.

This is intentionally application data rather than database seed data. A
course slug is persisted on a learner's profile, so the catalog must be
available before a database is seeded and must not acquire a new identity when
seed rows are rebuilt.

The map is curriculum-neutral: Novi supports several exam frameworks, but
claiming that one universal list is the legal syllabus for AP, IB, GCSE and
Gaokao would be false. The selected framework is retained as recommendation
context while this map supplies a complete, stable learning spine for every
grade and subject the product supports.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class GradeSpec:
    stage: str
    slug: str
    label: str
    age_range: str
    level: int


@dataclass(frozen=True, slots=True)
class CourseLevel:
    title: str
    skills: tuple[str, str, str]


@dataclass(frozen=True, slots=True)
class CourseDefinition:
    slug: str
    stage: str
    grade: str
    subject_slug: str
    name: str
    description: str
    skills: tuple[str, str, str]
    requirement: str
    level: int


GRADE_SPECS: tuple[GradeSpec, ...] = (
    GradeSpec("middle", "6", "Grade 6", "Ages 11-12", 1),
    GradeSpec("middle", "7", "Grade 7", "Ages 12-13", 1),
    GradeSpec("middle", "8", "Grade 8", "Ages 13-14", 2),
    GradeSpec("high", "9", "Grade 9", "Ages 14-15", 2),
    GradeSpec("high", "10", "Grade 10", "Ages 15-16", 2),
    GradeSpec("high", "11", "Grade 11", "Ages 16-17", 3),
    GradeSpec("high", "12", "Grade 12", "Ages 17-18", 4),
    GradeSpec("college", "freshman", "College freshman", "Typically 18-19", 3),
    GradeSpec("college", "sophomore", "College sophomore", "Typically 19-20", 3),
    GradeSpec("college", "junior", "College junior", "Typically 20-21", 4),
    GradeSpec("college", "senior", "College senior", "Typically 21-22", 4),
    GradeSpec("college", "grad", "Graduate study", "Typically 21+", 5),
    GradeSpec("other", "adult", "Adult learner", "Ages 18+", 2),
    GradeSpec("other", "self-taught", "Self-taught", "Any age", 2),
)

STAGES = ["middle", "high", "college", "other"]
GRADES_BY_STAGE: dict[str, list[str]] = {
    stage: [spec.slug for spec in GRADE_SPECS if spec.stage == stage] for stage in STAGES
}

FOCUS_GOALS: dict[str, tuple[str, str]] = {
    "build_foundations": (
        "Build foundations",
        "Repair prerequisite gaps before moving ahead.",
    ),
    "catch_up": (
        "Catch up",
        "Get back in step with the current class.",
    ),
    "improve_grades": (
        "Improve grades",
        "Turn understanding into stronger class results.",
    ),
    "exam_readiness": (
        "Prepare for an exam",
        "Practice recall, timing and common exam patterns.",
    ),
    "get_ahead": (
        "Get ahead",
        "Preview the next ideas before class reaches them.",
    ),
    "build_confidence": (
        "Build confidence",
        "Make the subject feel predictable and manageable.",
    ),
}

# Five cumulative levels per subject. GradeSpec.level selects one level; the
# existing concept graph uses the same 1...5 scale, so course progress can be
# computed from real concept evidence without a second mapping table.
SUBJECT_TRACKS: dict[str, tuple[CourseLevel, ...]] = {
    "mathematics": (
        CourseLevel(
            "Number Sense & Pre-Algebra",
            (
                "ratios and proportional reasoning",
                "fraction and integer operations",
                "variables and expressions"
            ),
        ),
        CourseLevel(
            "Algebra & Geometry",
            ("linear equations and functions", "geometry and measurement", "probability and data"),
        ),
        CourseLevel(
            "Functions, Trigonometry & Statistics",
            (
                "polynomial and exponential functions",
                "trigonometric modeling",
                "distributions and data analysis"
            ),
        ),
        CourseLevel(
            "Calculus & Probability",
            (
                "limits, derivatives and integrals",
                "sequences and series",
                "hypothesis testing and Bayes reasoning"
            ),
        ),
        CourseLevel(
            "Advanced Mathematical Modeling",
            (
                "differential equations",
                "linear algebra and eigenvectors",
                "proof and mathematical modeling"
            ),
        ),
    ),
    "physics": (
        CourseLevel(
            "Measurement, Forces & Energy",
            ("units and measurement", "force diagrams", "energy and simple machines"),
        ),
        CourseLevel(
            "Motion, Waves & Circuits",
            (
                "kinematics and Newton's laws",
                "waves and optics",
                "current, resistance and circuits"
            ),
        ),
        CourseLevel(
            "Mechanics & Thermodynamics",
            ("momentum and circular motion", "work, energy and gravitation", "thermal systems"),
        ),
        CourseLevel(
            "Fields & Modern Physics",
            (
                "electric and magnetic fields",
                "entropy and thermodynamics",
                "relativity and quantum foundations"
            ),
        ),
        CourseLevel(
            "Advanced Physical Modeling",
            (
                "differential models of physical systems",
                "experimental design and uncertainty",
                "computational simulation"
            ),
        ),
    ),
    "chemistry": (
        CourseLevel(
            "Matter & Atomic Foundations",
            (
                "atomic structure",
                "states and properties of matter",
                "measurement in the laboratory"
            ),
        ),
        CourseLevel(
            "Bonding & Reactions",
            ("periodic trends and bonding", "reaction types", "moles and stoichiometry"),
        ),
        CourseLevel(
            "Quantitative & Organic Chemistry",
            ("acids and bases", "thermochemistry", "organic functional groups"),
        ),
        CourseLevel(
            "Equilibrium, Kinetics & Electrochemistry",
            ("chemical equilibrium", "reaction kinetics", "redox and electrochemistry"),
        ),
        CourseLevel(
            "Advanced Chemical Systems",
            (
                "reaction mechanisms",
                "instrumental and quantitative analysis",
                "independent chemical investigation"
            ),
        ),
    ),
    "biology": (
        CourseLevel(
            "Cells & Ecosystems",
            ("cell structure and transport", "photosynthesis", "ecosystems and energy flow"),
        ),
        CourseLevel(
            "Genetics, Evolution & Organisms",
            ("mitosis and meiosis", "Mendelian genetics", "natural selection"),
        ),
        CourseLevel(
            "Molecular Biology & Homeostasis",
            ("DNA replication and protein synthesis", "cellular respiration", "homeostasis"),
        ),
        CourseLevel(
            "Systems Biology & Biotechnology",
            (
                "nervous and immune systems",
                "gene regulation and biotechnology",
                "population and systems modeling"
            ),
        ),
        CourseLevel(
            "Biological Research",
            (
                "experimental design and bioethics",
                "computational biology",
                "independent literature and lab research"
            ),
        ),
    ),
    "computer-science": (
        CourseLevel(
            "Computational Thinking",
            ("variables and data types", "control flow", "decomposing problems into algorithms"),
        ),
        CourseLevel(
            "Programming & Web Foundations",
            ("functions and collections", "HTTP and APIs", "version control and testing"),
        ),
        CourseLevel(
            "Data Structures & Systems",
            ("hash maps, trees and graphs", "algorithmic complexity", "databases and SQL"),
        ),
        CourseLevel(
            "AI, Algorithms & Software Design",
            (
                "advanced algorithms",
                "neural networks and embeddings",
                "reliable software architecture"
            ),
        ),
        CourseLevel(
            "Advanced Computing Research",
            (
                "research methods in computing",
                "scalable and secure systems",
                "independent implementation and evaluation"
            ),
        ),
    ),
    "economics": (
        CourseLevel(
            "Choices & Markets",
            ("scarcity and trade-offs", "incentives", "supply and demand"),
        ),
        CourseLevel(
            "Microeconomics",
            ("elasticity", "consumer and producer decisions", "market structures"),
        ),
        CourseLevel(
            "Macroeconomics & Trade",
            (
                "GDP, inflation and unemployment",
                "monetary and fiscal policy",
                "comparative advantage"
            ),
        ),
        CourseLevel(
            "Econometrics & Strategy",
            ("causal reasoning with data", "game theory", "policy and market evaluation"),
        ),
        CourseLevel(
            "Economic Research & Policy",
            ("advanced econometric design", "research synthesis", "policy communication"),
        ),
    ),
    "history": (
        CourseLevel(
            "Historical Evidence & Civilizations",
            ("chronology and causation", "reading primary sources", "comparing early societies"),
        ),
        CourseLevel(
            "World History & Revolutions",
            (
                "industrial and political revolutions",
                "empire and resistance",
                "evidence-based historical writing"
            ),
        ),
        CourseLevel(
            "Modern Global History",
            ("world wars and the Cold War", "decolonisation", "connecting local and global change"),
        ),
        CourseLevel(
            "Historiography & Comparative History",
            (
                "competing historical interpretations",
                "comparative case studies",
                "archival source criticism"
            ),
        ),
        CourseLevel(
            "Historical Research",
            (
                "research question design",
                "primary-source methodology",
                "original historical argument"
            ),
        ),
    ),
    "geography": (
        CourseLevel(
            "Earth Systems & Maps",
            (
                "map and spatial literacy",
                "weather and the water cycle",
                "landforms and plate tectonics"
            ),
        ),
        CourseLevel(
            "Human & Physical Geography",
            (
                "population and migration",
                "resources and development",
                "physical landscape processes"
            ),
        ),
        CourseLevel(
            "Urbanisation & Climate",
            ("urban systems", "climate change", "human-environment relationships"),
        ),
        CourseLevel(
            "Geospatial Analysis & Sustainability",
            ("GIS and spatial evidence", "sustainability trade-offs", "regional planning"),
        ),
        CourseLevel(
            "Geographic Research",
            (
                "fieldwork and spatial methods",
                "advanced geospatial analysis",
                "independent place-based research"
            ),
        ),
    ),
    "psychology": (
        CourseLevel(
            "Behavior & Mind",
            ("observation and evidence", "learning and memory basics", "emotion and behavior"),
        ),
        CourseLevel(
            "Development, Learning & Research",
            ("development across the lifespan", "conditioning", "ethical research methods"),
        ),
        CourseLevel(
            "Cognition & Social Psychology",
            ("memory models", "cognitive biases", "social influence and identity"),
        ),
        CourseLevel(
            "Clinical & Biological Psychology",
            (
                "brain-behavior relationships",
                "mental health frameworks",
                "evaluating psychological evidence"
            ),
        ),
        CourseLevel(
            "Psychological Research",
            (
                "advanced study design",
                "statistical interpretation",
                "replicable independent research"
            ),
        ),
    ),
    "languages": (
        CourseLevel(
            "Foundations of Communication",
            ("high-frequency vocabulary", "basic word order", "listening and pronunciation"),
        ),
        CourseLevel(
            "Everyday Fluency",
            ("verb tenses", "conversation strategies", "reading everyday texts"),
        ),
        CourseLevel(
            "Academic Communication",
            ("conditionals and complex sentences", "structured writing", "register and tone"),
        ),
        CourseLevel(
            "Advanced Language & Culture",
            ("idiom and collocation", "literary and media analysis", "sustained spoken argument"),
        ),
        CourseLevel(
            "Professional & Research Fluency",
            (
                "specialist vocabulary",
                "translation and intercultural nuance",
                "research and presentation"
            ),
        ),
    ),
    "literature": (
        CourseLevel(
            "Reading & Narrative",
            ("close reading", "plot, character and setting", "using quotations as evidence"),
        ),
        CourseLevel(
            "Genre, Voice & Evidence",
            ("narrative perspective", "metaphor and imagery", "paragraph-level argument"),
        ),
        CourseLevel(
            "Literary Analysis & Composition",
            ("thesis statements", "essay structure", "historical and cultural context"),
        ),
        CourseLevel(
            "Comparative Literature & Theory",
            ("comparing texts and traditions", "critical lenses", "independent analytical writing"),
        ),
        CourseLevel(
            "Literary Research",
            (
                "scholarly source evaluation",
                "original critical argument",
                "long-form research writing"
            ),
        ),
    ),
    "art": (
        CourseLevel(
            "Visual Foundations",
            ("line, shape and composition", "color theory", "observational drawing"),
        ),
        CourseLevel(
            "Studio Practice & Design",
            (
                "perspective and spatial construction",
                "material experimentation",
                "iterative design"
            ),
        ),
        CourseLevel(
            "Portfolio & Visual Culture",
            (
                "typography and visual communication",
                "art and design history",
                "building and explaining a portfolio"
            ),
        ),
        CourseLevel(
            "Advanced Studio & Critique",
            (
                "sustained creative inquiry",
                "professional critique",
                "curating a coherent body of work"
            ),
        ),
        CourseLevel(
            "Creative Research & Practice",
            (
                "practice-led research",
                "critical writing",
                "independent exhibition or design project"
            ),
        ),
    ),
    "business": (
        CourseLevel(
            "Enterprise & Financial Literacy",
            ("needs, value and exchange", "personal and business budgets", "ethical enterprise"),
        ),
        CourseLevel(
            "Organizations & Marketing",
            ("business models", "customers and marketing", "teams and operations"),
        ),
        CourseLevel(
            "Accounting, Strategy & Entrepreneurship",
            ("financial statements", "unit economics", "competitive and startup strategy"),
        ),
        CourseLevel(
            "Finance, Operations & Analytics",
            (
                "investment and financing decisions",
                "process and supply-chain design",
                "evidence-based management"
            ),
        ),
        CourseLevel(
            "Business Research & Leadership",
            ("organizational research", "governance and leadership", "capstone strategy"),
        ),
    ),
    "engineering": (
        CourseLevel(
            "Design & Making",
            ("defining constraints", "sketching and prototyping", "testing and iteration"),
        ),
        CourseLevel(
            "Mechanics, Circuits & CAD",
            ("free-body diagrams", "basic circuits", "computer-aided design"),
        ),
        CourseLevel(
            "Systems Engineering",
            (
                "stress and strain",
                "system requirements and trade-offs",
                "measurement and validation"
            ),
        ),
        CourseLevel(
            "Control, Materials & Optimization",
            ("control systems", "materials selection", "optimization under constraints"),
        ),
        CourseLevel(
            "Engineering Capstone & Research",
            (
                "advanced modeling",
                "safety, ethics and reliability",
                "design-build-test documentation"
            ),
        ),
    ),
}

SCHOOL_REQUIRED_SUBJECTS = frozenset(
    {
        "mathematics",
        "physics",
        "chemistry",
        "biology",
        "history",
        "geography",
        "languages",
        "literature",
        "art",
    }
)

FRAMEWORK_NOTE = (
    "Novi's grade map is a curriculum-neutral learning spine. Your selected "
    "school or exam framework is used as context; exact local requirements can differ."
)


def grade_spec(stage: str, grade: str) -> GradeSpec | None:
    return next(
        (spec for spec in GRADE_SPECS if spec.stage == stage and spec.slug == grade),
        None,
    )


def allowed_grades(stage: str | None = None) -> list[str]:
    if stage in GRADES_BY_STAGE:
        return list(GRADES_BY_STAGE[stage])
    return [spec.slug for spec in GRADE_SPECS]


def make_course_slug(stage: str, grade: str, subject_slug: str) -> str:
    return f"{stage}-{grade}-{subject_slug}"


def _description(spec: GradeSpec, track: CourseLevel) -> str:
    a, b, c = track.skills
    return f"For {spec.label}, this course develops {a}, {b}, and {c}."


def courses_for_grade(stage: str, grade: str) -> tuple[CourseDefinition, ...]:
    spec = grade_spec(stage, grade)
    if spec is None:
        return ()
    courses = []
    for subject_slug, levels in SUBJECT_TRACKS.items():
        track = levels[spec.level - 1]
        courses.append(
            CourseDefinition(
                slug=make_course_slug(stage, grade, subject_slug),
                stage=stage,
                grade=grade,
                subject_slug=subject_slug,
                name=track.title,
                description=_description(spec, track),
                skills=track.skills,
                requirement=(
                    "required"
                    if stage in {"middle", "high"}
                    and subject_slug in SCHOOL_REQUIRED_SUBJECTS
                    else "recommended"
                ),
                level=spec.level,
            )
        )
    return tuple(courses)


COURSES_BY_SLUG: dict[str, CourseDefinition] = {
    course.slug: course
    for spec in GRADE_SPECS
    for course in courses_for_grade(spec.stage, spec.slug)
}


def course_for_slug(slug: str) -> CourseDefinition | None:
    return COURSES_BY_SLUG.get(slug)


def remap_courses(
    stage: str,
    grade: str,
    selections: list[dict[str, str]],
    extra_subjects: list[str] | None = None,
) -> list[dict[str, str]]:
    """Move saved picks onto another grade's catalog, keeping local titles.

    A grade change must not invent a second profile. The learner's subjects and
    class names travel with them; only the canonical slug is rewritten.
    """
    available = {course.subject_slug: course for course in courses_for_grade(stage, grade)}
    out: list[dict[str, str]] = []
    seen: set[str] = set()

    def add(subject_slug: str, name: str) -> None:
        course = available.get(subject_slug)
        if course is None or course.slug in seen:
            return
        seen.add(course.slug)
        out.append({"course_slug": course.slug, "name": name})

    for item in selections:
        slug = item.get("course_slug", "")
        course = course_for_slug(slug)
        subject = course.subject_slug if course else (slug if slug in available else None)
        if subject:
            add(subject, item.get("name", ""))
    for subject_slug in extra_subjects or []:
        add(subject_slug, "")
    return out


def inferred_courses(stage: str, grade: str, subject_slugs: list[str]) -> list[dict[str, str]]:
    """Build canonical selections for an old profile that only stored subjects."""
    return remap_courses(stage, grade, [], extra_subjects=subject_slugs)


def focus_goal_label(slug: str | None) -> str | None:
    if not slug or slug not in FOCUS_GOALS:
        return None
    return FOCUS_GOALS[slug][0]
