"""Passwords and tokens.

Argon2id for passwords. Access tokens are JWTs the API verifies without a
database round trip; refresh tokens are opaque random strings whose SHA-256 is
the session row, so logout is a delete that actually revokes.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets
import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError

from novi.config import get_settings

_hasher = PasswordHasher()


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, password_hash: str) -> bool:
    try:
        _hasher.verify(password_hash, password)
    except (VerifyMismatchError, InvalidHashError, ValueError):
        return False
    return True


def create_access_token(user_id: uuid.UUID, *, is_admin: bool = False) -> tuple[str, int]:
    s = get_settings()
    now = datetime.now(UTC)
    ttl = s.access_token_ttl_seconds
    payload = {
        "sub": str(user_id),
        "typ": "access",
        "adm": is_admin,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=ttl)).timestamp()),
        "jti": uuid.uuid4().hex,
    }
    return jwt.encode(payload, s.jwt_secret, algorithm=s.jwt_algorithm), ttl


def decode_access_token(token: str) -> dict[str, Any] | None:
    s = get_settings()
    try:
        payload = jwt.decode(
            token,
            s.jwt_secret,
            algorithms=[s.jwt_algorithm],
            options={"require": ["exp", "sub", "iat", "typ"]},
        )
    except jwt.PyJWTError:
        return None
    return payload if payload.get("typ") == "access" else None


def needs_rehash(password_hash: str) -> bool:
    try:
        return _hasher.check_needs_rehash(password_hash)
    except (InvalidHashError, ValueError):
        return False


def new_opaque_token() -> str:
    return secrets.token_urlsafe(32)


def fingerprint(token: str) -> str:
    """SHA-256 is right here and Argon2 is not: the token is already 256 bits
    of uniform randomness, so there is nothing to brute-force, and refresh runs
    on app launch where a 100ms KDF would be felt."""
    return hashlib.sha256(token.encode()).hexdigest()


def secret_matches(presented: str, expected: str) -> bool:
    """Constant-time compare of two secrets.

    Both sides are hashed first so a length mismatch cannot throw (hmac's
    compare_digest requires equal-length bytes) and cannot leak through the
    exception path.
    """
    left = hashlib.sha256(presented.encode()).digest()
    right = hashlib.sha256(expected.encode()).digest()
    return hmac.compare_digest(left, right)
