from __future__ import annotations

import uuid

from pydantic import BaseModel, Field

from novi.schemas.auth import UserOut
from novi.schemas.common import ORMModel

# The allowed values, in one place. The client's onboarding options carry the
# same slugs, and these are what the API validates against — a renamed label on
# the client cannot silently become a value the server rejects.
STAGES = ["middle", "high", "college", "other"]
CURRICULA = ["AP", "IB", "SAT", "ACT", "GCSE", "A-Level", "Gaokao", "Other"]
LEARNING_PREFERENCES = [
    "short_video", "long_explanation", "visual", "real_world", "tutorials",
    "projects", "discussions", "news", "case_studies", "practice",
]
GOALS = [
    "improve_grades", "exam_prep", "learn_new", "build_projects",
    "explore_careers", "go_deeper", "college_prep", "curiosity",
]
# Grade / year, keyed by stage. The slug is what ranking and the tutor read.
GRADES_BY_STAGE: dict[str, list[str]] = {
    "middle": ["6", "7", "8"],
    "high": ["9", "10", "11", "12"],
    "college": ["freshman", "sophomore", "junior", "senior", "grad"],
    "other": ["adult", "self-taught"],
}


def allowed_grades(stage: str | None) -> list[str]:
    if stage and stage in GRADES_BY_STAGE:
        return GRADES_BY_STAGE[stage]
    return [g for grades in GRADES_BY_STAGE.values() for g in grades]


class ProfileOut(ORMModel):
    stage: str | None = None
    grade: str | None = None
    curriculum: str | None = None
    subject_order: list[str] = Field(default_factory=list)
    subject_interests: dict[str, float] = Field(default_factory=dict)
    weak_subjects: list[str] = Field(default_factory=list)
    learning_preferences: list[str] = Field(default_factory=list)
    goals: list[str] = Field(default_factory=list)
    language: str = "en"
    bio: str = ""


class OnboardingRequest(BaseModel):
    """The whole questionnaire, submitted once at the end.

    One request rather than a PATCH per step: a learner who abandons on step
    three should leave no half-built profile for the feed to rank against.
    """

    stage: str
    grade: str = Field(min_length=1, max_length=32)
    curriculum: str | None = None
    # Order is priority and it is preserved — the first subject leads the feed.
    subject_slugs: list[str] = Field(min_length=1, max_length=20)
    # Subset of subject_slugs: the classes they said they are stuck on.
    weak_subject_slugs: list[str] = Field(min_length=1, max_length=20)
    learning_preferences: list[str] = Field(default_factory=list, max_length=12)
    goals: list[str] = Field(default_factory=list, max_length=10)
    language: str = "en"


class ProfileUpdate(BaseModel):
    display_name: str | None = Field(default=None, max_length=80)
    bio: str | None = Field(default=None, max_length=500)
    stage: str | None = None
    grade: str | None = Field(default=None, max_length=32)
    curriculum: str | None = None
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
