# ruff: noqa: UP007, UP035
"""within-subject focus areas on the learning profile

Revision ID: d4b8c2e91a70
Revises: c31a97e4b6f2
Create Date: 2026-09-16 23:10:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "d4b8c2e91a70"
down_revision: Union[str, Sequence[str], None] = "c31a97e4b6f2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column(
            "focus_areas",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default="{}",
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column("profiles", "focus_areas")
