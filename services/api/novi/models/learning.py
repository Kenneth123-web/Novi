"""Behaviour, knowledge, quizzes, the passport and projects."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from novi.core.crypto import EncryptedJSON, EncryptedText
from novi.models.base import Base, TimestampMixin, uuid_pk

INTERACTION_TYPES = (
    "VIEW",
    "LIKE",
    "UNLIKE",
    "SAVE",
    "UNSAVE",
    "SHARE",
    "SKIP",
    "SEARCH",
    "ASK",
    "QUIZ_START",
    "QUIZ_COMPLETE",
    "CONCEPT_OPEN",
    "MARK_LEARNED",
    "PROJECT_CREATE",
)

# The mastery ladder. Ordered, and the order is the whole point: progress only
# ever moves forward, so a stray VIEW after a quiz cannot demote a concept the
# learner has already practised.
MASTERY_STATES = ("discovered", "viewed", "explored", "practiced", "learned", "mastered")
MASTERY_RANK = {state: i for i, state in enumerate(MASTERY_STATES)}


class Interaction(Base):
    """Append-only. Every derived table can be rebuilt from this one."""

    __tablename__ = "interactions"
    __table_args__ = (
        Index("ix_interactions_user_ts", "user_id", "occurred_at"),
        Index("ix_interactions_type_ts", "kind", "occurred_at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    kind: Mapped[str] = mapped_column(String(24), nullable=False)
    content_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("content.id", ondelete="SET NULL"), index=True
    )
    concept_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("concepts.id", ondelete="SET NULL"), index=True
    )
    # Seconds of attention. The single most informative signal we collect: a
    # like is one bit, dwell time is a measurement.
    dwell_seconds: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    context: Mapped[dict] = mapped_column(JSONB, nullable=False, default=dict, server_default="{}")
    occurred_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class SavedContent(Base):
    __tablename__ = "saved_content"
    __table_args__ = (UniqueConstraint("user_id", "content_id", name="uq_saved_pair"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    content_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("content.id", ondelete="CASCADE"), nullable=False, index=True
    )
    collection: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class ContentLike(Base):
    __tablename__ = "content_likes"
    __table_args__ = (UniqueConstraint("user_id", "content_id", name="uq_like_pair"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    content_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("content.id", ondelete="CASCADE"), nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class LearningProgress(Base, TimestampMixin):
    """One row per user x concept — the knowledge model.

    `mastery` never moves backwards (see `MASTERY_RANK`), and `confidence` is
    kept separately because they answer different questions: mastery is what
    the learner has *done*, confidence is how well they did it. A quiz scored
    40% still counts as "practiced".
    """

    __tablename__ = "learning_progress"
    __table_args__ = (
        UniqueConstraint("user_id", "concept_id", name="uq_progress_pair"),
        Index("ix_progress_user_mastery", "user_id", "mastery"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    concept_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    mastery: Mapped[str] = mapped_column(String(16), nullable=False, default="discovered")
    confidence: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    views: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    quiz_attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    best_quiz_score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    last_touched_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Question(Base):
    """A question the learner asked, and the AI answer it produced."""

    __tablename__ = "questions"
    __table_args__ = (Index("ix_questions_user_created", "user_id", "created_at"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    text_: Mapped[str] = mapped_column("text", EncryptedText, nullable=False)
    mode: Mapped[str] = mapped_column(String(24), nullable=False, default="explain")
    # Where the question came from, if it came from somewhere.
    content_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("content.id", ondelete="SET NULL")
    )
    concept_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("concepts.id", ondelete="SET NULL")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    answer: Mapped[AIResponse | None] = relationship(
        back_populates="question", uselist=False, cascade="all, delete-orphan", lazy="selectin"
    )


class AIResponse(Base):
    """A structured answer. Stored whole so the page can be reopened offline.

    `payload` is the parsed JSON the model returned — summary, explanation,
    example, misconception, related concepts, search queries. Keeping it as
    JSONB rather than columns means a prompt revision that adds a section does
    not need a migration.
    """

    __tablename__ = "ai_responses"

    id: Mapped[uuid.UUID] = uuid_pk()
    question_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("questions.id", ondelete="CASCADE"), nullable=False, unique=True, index=True
    )
    payload: Mapped[dict] = mapped_column(EncryptedJSON, nullable=False, default=dict)
    model: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    prompt_version: Mapped[str] = mapped_column(String(24), nullable=False, default="")
    input_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    output_tokens: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    latency_ms: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    cost_usd: Mapped[float] = mapped_column(Numeric(12, 6), nullable=False, default=0)
    feedback: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    question: Mapped[Question] = relationship(back_populates="answer")


class Quiz(Base):
    __tablename__ = "quizzes"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    concept_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )
    difficulty: Mapped[int] = mapped_column(Integer, nullable=False, default=2)
    model: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    score: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )

    questions: Mapped[list[QuizQuestion]] = relationship(
        back_populates="quiz",
        cascade="all, delete-orphan",
        order_by="QuizQuestion.ordinal",
        lazy="selectin",
    )


class QuizQuestion(Base):
    """The key lives here and is stripped from the response schema.

    Grading happens on the server and the client is never sent `correct_index`
    until it has answered. Hiding an answer in the UI while shipping it in the
    payload is not hiding it.
    """

    __tablename__ = "quiz_questions"

    id: Mapped[uuid.UUID] = uuid_pk()
    quiz_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("quizzes.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ordinal: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    options: Mapped[list[str]] = mapped_column(JSONB, nullable=False, default=list)
    correct_index: Mapped[int] = mapped_column(Integer, nullable=False)
    explanation: Mapped[str] = mapped_column(Text, nullable=False, default="")

    quiz: Mapped[Quiz] = relationship(back_populates="questions")


class QuizResult(Base):
    __tablename__ = "quiz_results"
    __table_args__ = (UniqueConstraint("quiz_id", "question_id", name="uq_quiz_result_pair"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    quiz_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("quizzes.id", ondelete="CASCADE"), nullable=False, index=True
    )
    question_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("quiz_questions.id", ondelete="CASCADE"), nullable=False
    )
    selected_index: Mapped[int] = mapped_column(Integer, nullable=False)
    is_correct: Mapped[bool] = mapped_column(Boolean, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class PassportStamp(Base):
    """A collectible milestone. Unique per (user, kind, key) so it is earned once."""

    __tablename__ = "passport_stamps"
    __table_args__ = (UniqueConstraint("user_id", "kind", "key", name="uq_stamp_identity"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # "concept" | "subject" | "milestone" | "project"
    kind: Mapped[str] = mapped_column(String(24), nullable=False)
    key: Mapped[str] = mapped_column(String(120), nullable=False)
    title: Mapped[str] = mapped_column(String(160), nullable=False)
    subtitle: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    icon: Mapped[str] = mapped_column(String(48), nullable=False, default="seal")
    earned_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=text("now()")
    )


class Project(Base, TimestampMixin):
    __tablename__ = "projects"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    skills: Mapped[list[str]] = mapped_column(ARRAY(String(48)), nullable=False, default=list)
    status: Mapped[str] = mapped_column(String(24), nullable=False, default="in_progress")
    progress: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    cover_seed: Mapped[str] = mapped_column(String(40), nullable=False, default="")

    concept_links: Mapped[list[ProjectConcept]] = relationship(
        back_populates="project", cascade="all, delete-orphan", lazy="selectin"
    )


class ProjectConcept(Base):
    __tablename__ = "project_concepts"
    __table_args__ = (UniqueConstraint("project_id", "concept_id", name="uq_project_concept"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    project_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("projects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    concept_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False, index=True
    )

    project: Mapped[Project] = relationship(back_populates="concept_links")
