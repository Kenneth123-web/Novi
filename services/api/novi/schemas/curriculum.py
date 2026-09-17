from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field


class CurrentCourseSelection(BaseModel):
    """One concrete class the learner says they are taking.

    `course_slug` links it to the stable grade map. `name` is the learner's
    exact local class title (for example "AP Calculus BC"); blank means use the
    canonical Novi title.
    """

    course_slug: str = Field(min_length=1, max_length=120)
    name: str = Field(default="", max_length=120)


class GradeSpecOut(BaseModel):
    stage: str
    slug: str
    label: str
    age_range: str
    level: int


class FocusGoalOptionOut(BaseModel):
    slug: str
    label: str
    description: str


class CurriculumCourseOut(BaseModel):
    slug: str
    subject_slug: str
    subject_name: str
    subject_description: str
    icon: str
    accent: str
    name: str
    description: str
    skills: list[str]
    requirement: str
    level: int


class SubjectAreaOut(BaseModel):
    slug: str
    name: str
    blurb: str
    concept_slugs: list[str]


class SubjectAreasOut(BaseModel):
    subject_slug: str
    subject_name: str
    areas: list[SubjectAreaOut]


class GradeCurriculumOut(BaseModel):
    stage: str
    grade: str
    grade_label: str
    age_range: str
    framework_note: str
    courses: list[CurriculumCourseOut]


class PassportCurriculumContextOut(BaseModel):
    stage: str
    grade: str
    grade_label: str
    age_range: str
    framework: str | None = None
    framework_note: str
    selection_source: str
    focus_subjects: list[str] = Field(default_factory=list)
    focus_goals: dict[str, str] = Field(default_factory=dict)


class PassportCourseConceptOut(BaseModel):
    id: str
    slug: str
    name: str
    mastery: str
    confidence: float


class PassportAreaOut(BaseModel):
    slug: str
    name: str


class PassportCourseOut(BaseModel):
    slug: str
    subject_slug: str
    subject_name: str
    icon: str
    accent: str
    name: str
    canonical_name: str
    description: str
    skills: list[str]
    requirement: str
    lane: str
    is_current: bool
    is_focus: bool
    focus_goal: str | None = None
    focus_areas: list[PassportAreaOut] = Field(default_factory=list)
    recommendation_reason: str
    status: str
    progress: float
    learned_concepts: int
    covered_concepts: int
    total_concepts: int
    concepts: list[PassportCourseConceptOut] = Field(default_factory=list)


class PassportSubjectConceptOut(BaseModel):
    id: str
    slug: str
    name: str
    mastery: str
    confidence: float


class PassportSubjectOut(BaseModel):
    subject_id: str
    slug: str
    name: str
    icon: str
    accent: str
    learned: int
    total_touched: int
    progress: float
    concepts: list[PassportSubjectConceptOut] = Field(default_factory=list)


class PassportStampOut(BaseModel):
    kind: str
    key: str
    title: str
    subtitle: str
    icon: str
    earned_at: datetime


class PassportOverviewOut(BaseModel):
    concepts_covered: int
    concepts_learned: int
    subjects: int
    projects: int
    sessions: int
    curriculum: PassportCurriculumContextOut | None = None
    course_map: list[PassportCourseOut] = Field(default_factory=list)
    subject_cards: list[PassportSubjectOut] = Field(default_factory=list)
    stamps: list[PassportStampOut] = Field(default_factory=list)
