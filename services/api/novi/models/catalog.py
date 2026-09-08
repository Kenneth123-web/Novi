"""Subjects and the concept graph.

Concepts, not just subjects, are the unit the product actually works in: the
tutor explains a concept, a quiz tests a concept, the passport stamps a
concept, and the recommender's "knowledge gap" is measured per concept.
"""

from __future__ import annotations

import uuid

from sqlalchemy import Float, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from novi.models.base import Base, TimestampMixin, uuid_pk


class Subject(Base, TimestampMixin):
    __tablename__ = "subjects"

    id: Mapped[uuid.UUID] = uuid_pk()
    # The slug is the real key: profiles, deep links and interest maps are all
    # keyed by it, so the catalog can be reseeded without orphaning anything.
    slug: Mapped[str] = mapped_column(String(48), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    icon: Mapped[str] = mapped_column(String(48), nullable=False, default="book")
    accent: Mapped[str] = mapped_column(String(8), nullable=False, default="")
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    concepts: Mapped[list[Concept]] = relationship(
        back_populates="subject", cascade="all, delete-orphan"
    )


class Concept(Base, TimestampMixin):
    __tablename__ = "concepts"
    __table_args__ = (Index("ix_concepts_subject_difficulty", "subject_id", "difficulty"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    slug: Mapped[str] = mapped_column(String(80), unique=True, nullable=False, index=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    subject_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("subjects.id", ondelete="CASCADE"), nullable=False, index=True
    )
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    # 1 (foundational) .. 5 (advanced). Used to keep a recommendation one step
    # ahead of the learner rather than ten.
    difficulty: Mapped[int] = mapped_column(Integer, nullable=False, default=2)
    sort_order: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    subject: Mapped[Subject] = relationship(back_populates="concepts")


class ConceptEdge(Base):
    """A directed edge in the concept graph: `from` leads to `to`.

    This is what makes the "learning rabbit hole" navigable and what lets the
    recommender suggest an *adjacent* concept rather than only what the learner
    already knows. Direction matters — derivatives lead to integrals, not the
    other way round — so the pair is stored once, not symmetrically.
    """

    __tablename__ = "concept_edges"
    __table_args__ = (
        UniqueConstraint("from_id", "to_id", name="uq_concept_edges_pair"),
        Index("ix_concept_edges_from", "from_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    from_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False
    )
    to_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("concepts.id", ondelete="CASCADE"), nullable=False
    )
    # "prerequisite" | "next" | "related"
    kind: Mapped[str] = mapped_column(String(24), nullable=False, default="related")
    weight: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
