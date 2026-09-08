"""Request-scoped dependencies."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from novi.core.errors import Forbidden, Unauthorized
from novi.core.logging import user_id_var
from novi.core.security import decode_access_token
from novi.db import get_db
from novi.models import User

# auto_error=False so a missing header produces our structured 401 rather than
# Starlette's bare {"detail": ...}.
_bearer = HTTPBearer(auto_error=False)

DB = Annotated[AsyncSession, Depends(get_db)]


async def current_user(
    request: Request,
    db: DB,
    creds: Annotated[HTTPAuthorizationCredentials | None, Depends(_bearer)] = None,
) -> User:
    if creds is None or not creds.credentials:
        raise Unauthorized("Sign in to continue")
    payload = decode_access_token(creds.credentials)
    if payload is None:
        raise Unauthorized("Your session has expired", code="TOKEN_INVALID")
    try:
        user_id = uuid.UUID(payload["sub"])
    except (KeyError, ValueError):
        raise Unauthorized("Your session has expired", code="TOKEN_INVALID") from None

    user = await db.get(User, user_id)
    if user is None or not user.is_active:
        # Same message as an expired token on purpose: whether an account
        # exists is not something an unauthenticated caller should be able to
        # probe.
        raise Unauthorized("Your session has expired", code="TOKEN_INVALID")

    user_id_var.set(str(user.id))
    request.state.user = user
    return user


CurrentUser = Annotated[User, Depends(current_user)]


async def current_admin(user: CurrentUser) -> User:
    if not user.is_admin:
        raise Forbidden("Administrator access required")
    return user


CurrentAdmin = Annotated[User, Depends(current_admin)]
