"""Registration, sign-in, refresh rotation.

Rules enforced here rather than in the routes, because they are easy to get
wrong and easy to lose in a refactor:

* Sign-in runs the Argon2 verify even for an unknown email, against a dummy
  hash. Skipping it makes "no such account" measurably faster than "wrong
  password", which is a working account-enumeration oracle.
* Refresh tokens rotate: presenting one spends it. A stolen token stops
  working as soon as the real client next refreshes.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from novi.config import get_settings
from novi.core.errors import Conflict, Unauthorized
from novi.core.logging import get_logger
from novi.core.security import (
    create_access_token,
    fingerprint,
    hash_password,
    new_opaque_token,
    verify_password,
)
from novi.models import Profile, Session, User
from novi.schemas.auth import TokenPair

logger = get_logger(__name__)

_DUMMY_HASH = hash_password(uuid.uuid4().hex)


def _now() -> datetime:
    return datetime.now(UTC)


async def _issue(db: AsyncSession, user: User, user_agent: str = "") -> TokenPair:
    s = get_settings()
    access, expires_in = create_access_token(user.id, is_admin=user.is_admin)
    refresh = new_opaque_token()
    db.add(
        Session(
            user_id=user.id,
            token_hash=fingerprint(refresh),
            expires_at=_now() + timedelta(seconds=s.refresh_token_ttl_seconds),
            created_at=_now(),
            user_agent=user_agent[:255],
        )
    )
    await db.flush()
    return TokenPair(access_token=access, refresh_token=refresh, expires_in=expires_in)


async def register(
    db: AsyncSession,
    *,
    email: str,
    username: str,
    password: str,
    display_name: str = "",
    user_agent: str = "",
) -> tuple[User, TokenPair]:
    email = email.strip().lower()
    username = username.strip()
    user = User(
        email=email,
        username=username,
        password_hash=hash_password(password),
        display_name=(display_name or username)[:80],
        avatar_seed=uuid.uuid4().hex[:12],
    )
    user.profile = Profile()
    db.add(user)
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        # Naming the colliding field is safe on registration — the caller is
        # about to discover it by trying another one anyway — and it is the
        # difference between a fixable form error and a dead end.
        field = "email" if "email" in str(exc.orig).lower() else "username"
        raise Conflict(
            f"That {field} is already taken",
            code="ALREADY_EXISTS",
            details={"field": field},
        ) from None

    tokens = await _issue(db, user, user_agent)
    logger.info("user_registered", extra={"new_user_id": str(user.id)})
    return user, tokens


async def login(
    db: AsyncSession, *, email: str, password: str, user_agent: str = ""
) -> tuple[User, TokenPair]:
    email = email.strip().lower()
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    ok = verify_password(password, user.password_hash if user else _DUMMY_HASH)
    if user is None or not ok or not user.is_active:
        raise Unauthorized("Email or password is incorrect", code="INVALID_CREDENTIALS")
    user.last_seen_at = _now()
    tokens = await _issue(db, user, user_agent)
    return user, tokens


async def refresh(db: AsyncSession, *, refresh_token: str, user_agent: str = "") -> TokenPair:
    row = (
        await db.execute(select(Session).where(Session.token_hash == fingerprint(refresh_token)))
    ).scalar_one_or_none()
    if row is None:
        raise Unauthorized("Please sign in again", code="TOKEN_INVALID")
    if row.expires_at <= _now():
        await db.delete(row)
        raise Unauthorized("Please sign in again", code="TOKEN_EXPIRED")
    user = await db.get(User, row.user_id)
    if user is None or not user.is_active:
        await db.delete(row)
        raise Unauthorized("Please sign in again", code="TOKEN_INVALID")

    await db.delete(row)  # rotation: the presented token is now spent
    await db.flush()
    return await _issue(db, user, user_agent)


async def logout(db: AsyncSession, *, refresh_token: str) -> None:
    """Idempotent — a retried logout is not an error."""
    await db.execute(delete(Session).where(Session.token_hash == fingerprint(refresh_token)))
