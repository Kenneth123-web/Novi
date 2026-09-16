"""Origin-only routes the Cloudflare console Worker calls.

Not part of the public API. Authenticated with the same shared secret the
Worker uses to accept ingest, so disabling an account in the console can
update Postgres as well as D1.
"""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Header
from pydantic import BaseModel
from sqlalchemy import delete

from novi.config import get_settings
from novi.core.deps import DB
from novi.core.errors import NotFound, Unauthorized
from novi.core.security import secret_matches
from novi.models import Session, User
from novi.schemas.common import Ok

router = APIRouter(prefix="/internal", tags=["internal"], include_in_schema=False)


class UserPatch(BaseModel):
    is_active: bool | None = None
    display_name: str | None = None


def _require_origin(secret: str | None) -> None:
    expected = get_settings().console_origin_secret
    if not expected:
        raise NotFound("No such route")
    if not secret or not secret_matches(secret, expected):
        raise Unauthorized("Origin secret rejected")


@router.patch("/users/{user_id}", response_model=Ok)
async def patch_user(
    user_id: uuid.UUID,
    body: UserPatch,
    db: DB,
    x_novi_origin_secret: str | None = Header(default=None),
) -> Ok:
    _require_origin(x_novi_origin_secret)
    user = await db.get(User, user_id)
    if user is None:
        raise NotFound("No such user")
    if body.is_active is not None:
        user.is_active = body.is_active
        if not body.is_active:
            # A disabled account must not keep spending a refresh token.
            await db.execute(delete(Session).where(Session.user_id == user.id))
    if body.display_name is not None:
        user.display_name = body.display_name[:80]
    return Ok()


@router.delete("/users/{user_id}/sessions", response_model=Ok)
async def revoke_sessions(
    user_id: uuid.UUID,
    db: DB,
    x_novi_origin_secret: str | None = Header(default=None),
) -> Ok:
    _require_origin(x_novi_origin_secret)
    await db.execute(delete(Session).where(Session.user_id == user_id))
    return Ok()
