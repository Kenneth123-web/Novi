# ruff: noqa: UP007, UP035
"""concrete courses and subject focus goals

Revision ID: c31a97e4b6f2
Revises: b7e4f1a90c2d
Create Date: 2026-09-16 22:20:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "c31a97e4b6f2"
down_revision: Union[str, Sequence[str], None] = "b7e4f1a90c2d"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column(
            "current_courses",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="[]",
            nullable=False,
        ),
    )
    op.add_column(
        "profiles",
        sa.Column(
            "focus_goals",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="{}",
            nullable=False,
        ),
    )

    # Profiles written before concrete courses existed retain their ordered
    # subjects. Convert each valid one to the corresponding deterministic
    # grade-course slug. Invalid legacy values stay out of the new field and
    # are handled as an honest customization-needed state by the API.
    op.execute(
        sa.text(
            """
            UPDATE profiles AS profile
            SET current_courses = COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'course_slug',
                            profile.stage || '-' || profile.grade || '-' || picked.subject_slug,
                            'name',
                            ''
                        )
                        ORDER BY picked.ordinal
                    )
                    FROM unnest(profile.subject_order)
                        WITH ORDINALITY AS picked(subject_slug, ordinal)
                    WHERE picked.subject_slug IN (
                        'mathematics', 'physics', 'chemistry', 'biology',
                        'computer-science', 'economics', 'history', 'geography',
                        'psychology', 'languages', 'literature', 'art',
                        'business', 'engineering'
                    )
                ),
                '[]'::jsonb
            )
            WHERE (profile.stage, profile.grade) IN (
                ('middle', '6'), ('middle', '7'), ('middle', '8'),
                ('high', '9'), ('high', '10'), ('high', '11'), ('high', '12'),
                ('college', 'freshman'), ('college', 'sophomore'),
                ('college', 'junior'), ('college', 'senior'), ('college', 'grad'),
                ('other', 'adult'), ('other', 'self-taught')
            )
            """
        )
    )


def downgrade() -> None:
    op.drop_column("profiles", "focus_goals")
    op.drop_column("profiles", "current_courses")
