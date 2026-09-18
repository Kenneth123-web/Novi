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

import asyncio
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from novi.config import get_settings
from novi.core.errors import Conflict, NotFound, Unauthorized
from novi.core.logging import get_logger
from novi.core.security import (
    create_access_token,
    fingerprint,
    hash_password,
    new_opaque_token,
    secret_matches,
    verify_password,
)
from novi.models import Profile, Session, User
from novi.schemas.auth import TokenPair
from novi.services import console_client

logger = get_logger(__name__)

_DUMMY_HASH = hash_password(uuid.uuid4().hex)

# Reserved developer account. The password is random and never shown; skip
# login issues a session without it. Email is the stable key — if a human
# later registers this address they get this row, which is the point.
DEV_SKIP_EMAIL = "developer@novi.app"
DEV_SKIP_USERNAME = "developer"


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
        password_hash=await asyncio.to_thread(hash_password, password),
        display_name=(display_name or username)[:80],
        avatar_seed=uuid.uuid4().hex[:12],
    )
    user.profile = Profile()
    db.add(user)
    try:
        await db.flush()
    except IntegrityError:
        await db.rollback()
        raise Conflict(
            "Account details are already in use",
            code="ALREADY_EXISTS",
        ) from None

    tokens = await _issue(db, user, user_agent)
    logger.info("user_registered", extra={"new_user_id": str(user.id)})
    console_client.spawn(
        console_client.report_account(
            user, event="registered", source="register", user_agent=user_agent
        )
    )
    return user, tokens


async def login(
    db: AsyncSession, *, email: str, password: str, user_agent: str = ""
) -> tuple[User, TokenPair]:
    email = email.strip().lower()
    user = (await db.execute(select(User).where(User.email == email))).scalar_one_or_none()
    ok = await asyncio.to_thread(
        verify_password, password, user.password_hash if user else _DUMMY_HASH
    )
    if user is None or not ok or not user.is_active:
        raise Unauthorized("Email or password is incorrect", code="INVALID_CREDENTIALS")
    if await console_client.is_blocked(str(user.id)):
        raise Unauthorized("Email or password is incorrect", code="INVALID_CREDENTIALS")
    user.last_seen_at = _now()
    tokens = await _issue(db, user, user_agent)
    console_client.spawn(
        console_client.report_account(
            user, event="logged_in", source="login", user_agent=user_agent
        )
    )
    return user, tokens


async def refresh(db: AsyncSession, *, refresh_token: str, user_agent: str = "") -> TokenPair:
    # Atomic consume: exactly one concurrent presenter can spend this token.
    spent = (
        await db.execute(
            delete(Session)
            .where(Session.token_hash == fingerprint(refresh_token))
            .returning(Session.user_id, Session.expires_at)
        )
    ).one_or_none()
    if spent is None:
        raise Unauthorized("Please sign in again", code="TOKEN_INVALID")
    user_id, expires_at = spent
    if expires_at <= _now():
        raise Unauthorized("Please sign in again", code="TOKEN_EXPIRED")
    user = await db.get(User, user_id)
    if user is None or not user.is_active or await console_client.is_blocked(str(user_id)):
        await db.execute(delete(Session).where(Session.user_id == user_id))
        raise Unauthorized("Please sign in again", code="TOKEN_INVALID")
    return await _issue(db, user, user_agent)


async def logout(db: AsyncSession, *, refresh_token: str) -> None:
    """Idempotent — a retried logout is not an error."""
    await db.execute(delete(Session).where(Session.token_hash == fingerprint(refresh_token)))


async def skip_login(
    db: AsyncSession, *, secret: str = "", user_agent: str = ""
) -> tuple[User, TokenPair]:
    """Mint a real session for the reserved developer user.

    The route is opt-in outside production and always requires a matching
    secret. Production never exposes it.
    """
    s = get_settings()
    if s.env == "production" or not s.dev_skip_enabled:
        raise NotFound("No such route")
    if not s.dev_skip_secret or not secret_matches(secret, s.dev_skip_secret):
        raise Unauthorized("Developer skip is not allowed", code="UNAUTHORIZED")

    user = (
        await db.execute(select(User).where(User.email == DEV_SKIP_EMAIL))
    ).scalar_one_or_none()
    if user is None:
        username = DEV_SKIP_USERNAME
        taken = (
            await db.execute(select(User.id).where(User.username == username))
        ).scalar_one_or_none()
        if taken is not None:
            username = f"developer_{uuid.uuid4().hex[:8]}"
        user = User(
            email=DEV_SKIP_EMAIL,
            username=username,
            password_hash=await asyncio.to_thread(hash_password, new_opaque_token()),
            display_name="Developer",
            avatar_seed="developer",
        )
        user.profile = Profile()
        db.add(user)
        try:
            await db.flush()
        except IntegrityError:
            await db.rollback()
            user = (
                await db.execute(select(User).where(User.email == DEV_SKIP_EMAIL))
            ).scalar_one()
    if not user.is_active or await console_client.is_blocked(str(user.id)):
        raise Unauthorized("Email or password is incorrect", code="INVALID_CREDENTIALS")

    # Skip is a login, not a reset. The client still opens the questionnaire
    # when grade / stuck-on subjects are missing; wiping onboarded_at here
    # made every Skip land on the welcome page even after the profile was
    # filled in.
    user.last_seen_at = _now()
    tokens = await _issue(db, user, user_agent)
    console_client.spawn(
        console_client.report_account(
            user, event="dev_skipped", source="dev-skip", user_agent=user_agent
        )
    )
    logger.info("dev_skip_login", extra={"user_id": str(user.id)})
    return user, tokens
