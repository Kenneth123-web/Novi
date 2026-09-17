from __future__ import annotations

import re
import uuid
from datetime import datetime

from pydantic import AliasChoices, BaseModel, EmailStr, Field, field_validator

from novi.schemas.common import ORMModel

USERNAME_RE = re.compile(r"^[a-zA-Z0-9_.-]{3,40}$")


def _check_password(v: str) -> str:
    if len(v) < 8:
        raise ValueError("Password must be at least 8 characters")
    if len(v) > 128:
        raise ValueError("Password must be at most 128 characters")
    if v.isdigit() or v.isalpha():
        raise ValueError("Password must mix letters with digits or symbols")
    return v


class RegisterRequest(BaseModel):
    email: EmailStr
    username: str = Field(min_length=3, max_length=40)
    password: str
    display_name: str = Field(default="", max_length=80)
    turnstile_token: str = Field(
        default="",
        validation_alias=AliasChoices(
            "turnstile_token", "cf-turnstile-response", "cf_turnstile_response"
        ),
    )

    @field_validator("username")
    @classmethod
    def _username(cls, v: str) -> str:
        if not USERNAME_RE.match(v):
            raise ValueError("Letters, digits, dot, dash and underscore only")
        return v

    @field_validator("password")
    @classmethod
    def _password(cls, v: str) -> str:
        return _check_password(v)


class LoginRequest(BaseModel):
    email: EmailStr
    password: str
    turnstile_token: str = Field(
        default="",
        validation_alias=AliasChoices(
            "turnstile_token", "cf-turnstile-response", "cf_turnstile_response"
        ),
    )


class CaptchaConfig(BaseModel):
    """Public Turnstile settings. The secret never leaves the siteverify Worker."""

    provider: str = "turnstile"
    enabled: bool
    sitekey: str
    action: str = "turnstile-spin-v1"
    widget_url: str = ""


class RefreshRequest(BaseModel):
    refresh_token: str


class DevSkipRequest(BaseModel):
    """Body for POST /auth/dev-skip. `secret` is required only when the
    server has DEV_SKIP_SECRET configured.

    `device_id` scopes the developer account to one install. Without it every
    skip shares a single row, so a freshly installed app inherits whatever
    profile and history the last tester left behind.
    """

    secret: str = ""
    device_id: str = Field(default="", max_length=64)


class TokenPair(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "Bearer"  # noqa: S105 — a scheme name, not a secret
    expires_in: int


class UserOut(ORMModel):
    id: uuid.UUID
    email: EmailStr
    username: str
    display_name: str
    avatar_seed: str
    is_admin: bool
    is_onboarded: bool
    created_at: datetime


class AuthResponse(BaseModel):
    user: UserOut
    tokens: TokenPair
