from __future__ import annotations

import uuid

from pydantic import BaseModel, Field

from novi.schemas.content import ContentOut, DiscussionOut

ASK_MODES = ["explain", "simple", "eli10", "deeper", "example", "compare"]


class AskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=2000)
    mode: str = "explain"
    # Where the question was asked from, so the tutor can see what the learner
    # was looking at when they got stuck.
    content_id: uuid.UUID | None = None
    concept_id: uuid.UUID | None = None


class Explanation(BaseModel):
    """The structured answer the client renders as sections.

    Every field except `summary` is optional: a missing section is skipped by
    the renderer, which is a better outcome than failing the whole request
    because the model omitted one heading.
    """

    concept: str = ""
    summary: str = ""
    simple_explanation: str = ""
    why_it_works: str = ""
    example: str = ""
    common_misconception: str = ""
    related_concepts: list[str] = Field(default_factory=list)
    search_queries: list[str] = Field(default_factory=list)


class AskResponse(BaseModel):
    question_id: uuid.UUID
    explanation: Explanation
    # The discovery rail below the answer — the reason the page does not end
    # when the explanation does.
    watch: list[ContentOut] = Field(default_factory=list)
    read: list[ContentOut] = Field(default_factory=list)
    discuss: list[DiscussionOut] = Field(default_factory=list)
    related_concepts: list[dict] = Field(default_factory=list)
    model: str = ""


class QuizRequest(BaseModel):
    concept_id: uuid.UUID
    count: int = Field(default=5, ge=3, le=10)
    difficulty: int | None = Field(default=None, ge=1, le=5)


class QuizQuestionOut(BaseModel):
    """Note the absence of `correct_index`. Grading is server-side, and a
    client that never receives the key cannot leak it."""

    id: uuid.UUID
    ordinal: int
    prompt: str
    options: list[str]


class QuizOut(BaseModel):
    id: uuid.UUID
    concept_id: uuid.UUID
    concept_name: str
    difficulty: int
    questions: list[QuizQuestionOut]


class QuizAnswer(BaseModel):
    question_id: uuid.UUID
    selected_index: int = Field(ge=0, le=3)


class QuizSubmission(BaseModel):
    answers: list[QuizAnswer] = Field(min_length=1, max_length=10)


class GradedAnswer(BaseModel):
    question_id: uuid.UUID
    selected_index: int
    correct_index: int
    is_correct: bool
    explanation: str


class StampOut(BaseModel):
    kind: str
    key: str
    title: str
    subtitle: str = ""
    icon: str = "seal"


class QuizResultOut(BaseModel):
    quiz_id: uuid.UUID
    score: float
    correct: int
    total: int
    answers: list[GradedAnswer]
    concept_mastery: str
    # Only stamps earned by *this* submission, so the client knows when to
    # play the celebration.
    new_stamps: list[StampOut] = Field(default_factory=list)


class SummarizeRequest(BaseModel):
    translate_to: str | None = Field(default=None, min_length=2, max_length=40)
