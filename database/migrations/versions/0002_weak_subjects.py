"""weak subjects on the learning profile

Revision ID: b7e4f1a90c2d
Revises: d9c26d2e7c0c
Create Date: 2026-09-16 00:10:00.000000

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "b7e4f1a90c2d"
down_revision: Union[str, Sequence[str], None] = "d9c26d2e7c0c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "profiles",
        sa.Column(
            "weak_subjects",
            postgresql.ARRAY(sa.String(length=48)),
            server_default="{}",
            nullable=False,
        ),
    )


def downgrade() -> None:
    op.drop_column("profiles", "weak_subjects")
