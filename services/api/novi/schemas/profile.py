from __future__ import annotations

import uuid

from pydantic import BaseModel, Field, field_validator

from novi.schemas.auth import UserOut
from novi.schemas.common import ORMModel
from novi.schemas.curriculum import CurrentCourseSelection

# The allowed values, in one place. The client's onboarding options carry the
# same slugs, and these are what the API validates against — a renamed label on
# the client cannot silently become a value the server rejects.
CURRICULA = ["AP", "IB", "SAT", "ACT", "GCSE", "A-Level", "Gaokao", "Other"]
LEARNING_PREFERENCES = [
    "short_video", "long_explanation", "visual", "real_world", "tutorials",
    "projects", "discussions", "news", "case_studies", "practice",
]
GOALS = [
    "improve_grades", "exam_prep", "learn_new", "build_projects",
    "explore_careers", "go_deeper",     "college_prep", "curiosity",
]


class ProfileOut(ORMModel):
    stage: str | None = None
    grade: str | None = None
    curriculum: str | None = None
    subject_order: list[str] = Field(default_factory=list)
    subject_interests: dict[str, float] = Field(default_factory=dict)
    weak_subjects: list[str] = Field(default_factory=list)
    current_courses: list[CurrentCourseSelection] = Field(default_factory=list)
    focus_goals: dict[str, str] = Field(default_factory=dict)
    learning_preferences: list[str] = Field(default_factory=list)
    goals: list[str] = Field(default_factory=list)
    language: str = "en"
    bio: str = ""

    @field_validator("current_courses", mode="before")
    @classmethod
    def _coerce_courses(cls, value: object) -> object:
        """A malformed historical JSON blob must not 500 /me."""
        if not isinstance(value, list):
            return []
        out: list[dict[str, str]] = []
        seen: set[str] = set()
        for raw in value:
            if not isinstance(raw, dict):
                continue
            slug = raw.get("course_slug")
            if not isinstance(slug, str) or not slug.strip() or slug in seen:
                continue
            seen.add(slug)
            name = raw.get("name", "")
            out.append(
                {
                    "course_slug": slug,
                    "name": " ".join(name.split()) if isinstance(name, str) else "",
                }
            )
        return out

    @field_validator("focus_goals", mode="before")
    @classmethod
    def _coerce_focus_goals(cls, value: object) -> object:
        if not isinstance(value, dict):
            return {}
        return {
            key: goal
            for key, goal in value.items()
            if isinstance(key, str) and isinstance(goal, str) and key and goal
        }


class OnboardingRequest(BaseModel):
    """The whole questionnaire, submitted once at the end.

    One request rather than a PATCH per step: a learner who abandons on step
    three should leave no half-built profile for the feed to rank against.
    """

    stage: str
    grade: str = Field(min_length=1, max_length=32)
    curriculum: str | None = None
    # New clients submit concrete grade-catalog courses. The two subject fields
    # remain optional compatibility inputs for clients released before courses
    # existed; the service converts them to canonical course selections.
    current_courses: list[CurrentCourseSelection] | None = Field(default=None, max_length=20)
    focus_subject_slugs: list[str] | None = Field(default=None, max_length=20)
    focus_goals: dict[str, str] = Field(default_factory=dict, max_length=20)
    subject_slugs: list[str] | None = Field(default=None, max_length=20)
    weak_subject_slugs: list[str] | None = Field(default=None, max_length=20)
    learning_preferences: list[str] = Field(default_factory=list, max_length=12)
    goals: list[str] = Field(default_factory=list, max_length=10)
    language: str = "en"


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=80)
    bio: str | None = Field(default=None, max_length=500)
    stage: str | None = None
    grade: str | None = Field(default=None, max_length=32)
    curriculum: str | None = None
    current_courses: list[CurrentCourseSelection] | None = Field(default=None, max_length=20)
    focus_subject_slugs: list[str] | None = Field(default=None, max_length=20)
    focus_goals: dict[str, str] | None = Field(default=None, max_length=20)
    # Compatibility inputs for the previous subject-only client.
    subject_slugs: list[str] | None = None
    weak_subject_slugs: list[str] | None = None
    learning_preferences: list[str] | None = None
    goals: list[str] | None = None
    language: str | None = Field(default=None, max_length=16)


class MeOut(BaseModel):
    user: UserOut
    profile: ProfileOut | None = None


class SubjectOut(ORMModel):
    id: uuid.UUID
    slug: str
    name: str
    description: str
    icon: str
    accent: str


class ConceptOut(ORMModel):
    id: uuid.UUID
    slug: str
    name: str
    subject_id: uuid.UUID
    description: str
    difficulty: int
