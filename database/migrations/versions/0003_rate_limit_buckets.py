"""shared production rate-limit buckets

Revision ID: 91a4f0d63e2b
Revises: b7e4f1a90c2d
Create Date: 2026-09-17 21:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "91a4f0d63e2b"
down_revision: str | Sequence[str] | None = "b7e4f1a90c2d"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "rate_limit_buckets",
        sa.Column("key", sa.String(length=255), nullable=False),
        sa.Column("count", sa.Integer(), nullable=False),
        sa.Column("window_started", sa.DateTime(timezone=True), nullable=False),
        sa.PrimaryKeyConstraint("key", name=op.f("pk_rate_limit_buckets")),
    )


def downgrade() -> None:
    op.drop_table("rate_limit_buckets")
