"""Application-level encryption at rest.

AES-256-GCM envelopes, dual-read. New writes are sealed; rows that predate
this module are returned unchanged. The iOS client never sees the envelope —
SQLAlchemy decrypts on the way out of the database, encrypts on the way in.

This is a defence for the operator, not a feature for the learner. A stolen
Postgres dump of questions and tutor answers is ciphertext. Rotating
JWT_SECRET independently of this key is why APP_ENCRYPTION_KEY exists; when
it is unset the key is derived from JWT_SECRET so a fresh clone still seals
without another environment variable.
"""

from __future__ import annotations

import base64
import hashlib
import json
import logging
import os
from typing import Any

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from sqlalchemy import Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator

from novi.config import get_settings

logger = logging.getLogger(__name__)

PREFIX = "nv1."
_AAD = b"novi-v1"
_NONCE_SIZE = 12
_JSON_SENTINEL = "_nv1"


def _key_bytes() -> bytes:
    s = get_settings()
    material = (s.app_encryption_key or s.jwt_secret).encode("utf-8")
    return hashlib.sha256(b"novi-at-rest-v1:" + material).digest()


def is_envelope(value: str) -> bool:
    return value.startswith(PREFIX)


def encrypt_text(plain: str) -> str:
    """Seal a string. Empty and already-sealed values pass through."""
    if not plain or is_envelope(plain):
        return plain
    try:
        nonce = os.urandom(_NONCE_SIZE)
        token = nonce + AESGCM(_key_bytes()).encrypt(nonce, plain.encode("utf-8"), _AAD)
        return PREFIX + base64.urlsafe_b64encode(token).decode("ascii")
    except Exception:
        # Fail open: a crypto library error must not 500 a learner's Ask.
        logger.exception("at_rest_encrypt_failed")
        return plain


def decrypt_text(value: str) -> str:
    """Open an envelope, or return plaintext that predates encryption."""
    if not value or not is_envelope(value):
        return value
    try:
        raw = base64.urlsafe_b64decode(value[len(PREFIX) :].encode("ascii"))
        nonce, rest = raw[:_NONCE_SIZE], raw[_NONCE_SIZE:]
        return AESGCM(_key_bytes()).decrypt(nonce, rest, _AAD).decode("utf-8")
    except Exception:
        logger.warning("at_rest_decrypt_failed")
        # Wrong key, or a truncated write. Do not echo ciphertext to a client.
        return ""


class EncryptedText(TypeDecorator):
    """TEXT column that seals on write and opens on read."""

    impl = Text
    cache_ok = True

    def process_bind_param(self, value: str | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        return encrypt_text(value)

    def process_result_value(self, value: str | None, dialect: Dialect) -> str | None:
        if value is None:
            return None
        return decrypt_text(value)


class EncryptedJSON(TypeDecorator):
    """JSONB column whose object is stored as a single sealed string.

    Legacy plaintext objects (anything not `{_nv1: "<envelope>"}`) are
    returned as-is, so existing tutor answers keep rendering.
    """

    impl = JSONB
    cache_ok = True

    def process_bind_param(self, value: Any, dialect: Dialect) -> dict[str, str] | None:
        if value is None:
            return None
        blob = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        return {_JSON_SENTINEL: encrypt_text(blob)}

    def process_result_value(self, value: Any, dialect: Dialect) -> Any:
        if value is None:
            return None
        if isinstance(value, dict) and set(value.keys()) == {_JSON_SENTINEL}:
            opened = decrypt_text(str(value[_JSON_SENTINEL]))
            if not opened:
                return {}
            try:
                parsed = json.loads(opened)
            except json.JSONDecodeError:
                return {}
            return parsed if isinstance(parsed, dict) else {}
        return value
