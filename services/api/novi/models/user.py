"""Accounts, the learning profile, and sessions."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from novi.models.base import Base, TimestampMixin, uuid_pk


class User(Base, TimestampMixin):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = uuid_pk()
    email: Mapped[str] = mapped_column(String(320), unique=True, nullable=False, index=True)
    username: Mapped[str] = mapped_column(String(40), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    display_name: Mapped[str] = mapped_column(String(80), nullable=False, default="")
    avatar_seed: Mapped[str] = mapped_column(String(40), nullable=False, default="")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    is_admin: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    onboarded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    profile: Mapped[Profile | None] = relationship(
        back_populates="user", uselist=False, cascade="all, delete-orphan", lazy="selectin"
    )

    @property
    def is_onboarded(self) -> bool:
        return self.onboarded_at is not None


class Profile(Base, TimestampMixin):
    """What onboarding collects. This is the input to every ranking decision.

    `subject_interests` is a JSONB map of subject-slug -> 0..1 rather than a
    join table, because it is read on every feed request and rewritten on every
    meaningful interaction; a table would mean N rows read and written where a
    single column does. It stays legible enough to debug by eye, which a packed
    embedding would not be.
    """

    __tablename__ = "profiles"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    stage: Mapped[str | None] = mapped_column(String(32))  # middle | high | college | other
    grade: Mapped[str | None] = mapped_column(String(32))
    curriculum: Mapped[str | None] = mapped_column(String(32))  # AP | IB | SAT | GCSE | ...

    # Ordered by the user during onboarding. Order is priority, and it is
    # preserved: the first subject leads the feed.
    subject_order: Mapped[list[str]] = mapped_column(
        ARRAY(String(48)), nullable=False, default=list
    )
    subject_interests: Mapped[dict[str, float]] = mapped_column(
        JSONB, nullable=False, default=dict, server_default="{}"
    )
    learning_preferences: Mapped[list[str]] = mapped_column(
        ARRAY(String(48)), nullable=False, default=list
    )
    # Subjects the learner said they are stuck on. Ranking boosts `gap` here
    # so the feed teaches the hard class rather than only the favourite one.
    weak_subjects: Mapped[list[str]] = mapped_column(
        ARRAY(String(48)), nullable=False, default=list, server_default="{}"
    )
    goals: Mapped[list[str]] = mapped_column(ARRAY(String(48)), nullable=False, default=list)

    language: Mapped[str] = mapped_column(String(16), nullable=False, default="en")
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="UTC")
    bio: Mapped[str] = mapped_column(Text, nullable=False, default="")
    interests_decayed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    user: Mapped[User] = relationship(back_populates="profile")


class Session(Base):
    """One refresh token, stored as a hash. Logout deletes the row."""

    __tablename__ = "sessions"
    __table_args__ = (Index("ix_sessions_user_expires", "user_id", "expires_at"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    user_agent: Mapped[str] = mapped_column(String(255), nullable=False, default="")
