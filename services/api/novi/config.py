"""Configuration, read from the environment.

The AI gateway key lives here and nowhere near the client. The app calls
`POST /v1/ask`; the API calls Gemini. A key shipped in an iOS binary is a key
anyone with a copy of the binary can extract.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

DEV_JWT_SECRET = "dev-only-insecure-secret-change-me"  # noqa: S105


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", "../../.env"), env_file_encoding="utf-8", extra="ignore"
    )

    env: Literal["development", "test", "production"] = "development"
    debug: bool = True
    log_level: str = "INFO"

    database_url: str = "postgresql+asyncpg://novi:novi@localhost:5432/novi"
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_echo: bool = False

    # ── Auth ─────────────────────────────────────────────────────────────────
    jwt_secret: str = DEV_JWT_SECRET
    jwt_algorithm: str = "HS256"
    access_token_ttl_seconds: int = 60 * 60 * 24 * 7
    refresh_token_ttl_seconds: int = 60 * 60 * 24 * 60

    # ── AI gateway (OpenAI-compatible, in front of Gemini) ───────────────────
    ai_base_url: str = "https://1pkapi.com/v1"
    ai_api_key: str | None = None

    # Which wire protocol the gateway speaks.
    #
    # "anthropic" is POST /v1/messages with x-api-key — the shape the
    # @ai-sdk/anthropic client uses. Measured against this gateway it is the
    # healthier of the two: it answers in ~38s with a structured, transient
    # rate_limit_error, where /v1/chat/completions hangs for 240s or reports
    # "All available accounts exhausted".
    ai_protocol: Literal["anthropic", "openai"] = "anthropic"

    # Haiku first, on purpose. It is the right model for this workload and it
    # is what we want the moment the gateway's account group can serve it.
    # Today it answers `model_not_found`, so the gateway walks this list and
    # uses the first model that is actually served — see AIGateway._resolve.
    # Wanting Haiku and being honest that it is not available yet are not in
    # conflict; silently pretending otherwise would be.
    ai_model: str = "claude-haiku-4-5"
    ai_model_fast: str = "claude-haiku-4-5"
    ai_model_fallbacks: list[str] = Field(
        default_factory=lambda: ["claude-sonnet-4-6", "claude-sonnet-5", "claude-opus-4-6"]
    )
    # Deliberately shorter than the client's 90s. The gateway currently takes
    # 120-240s to admit it has no capacity, and a learner watching a spinner
    # for two minutes before being told the tutor is offline is worse than
    # being told in forty-five seconds. Whichever side times out first decides
    # what the user reads, so the server has to lose that race on purpose.
    ai_timeout_seconds: float = 45.0
    ai_max_output_tokens: int = 2048

    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    @field_validator("ai_model_fallbacks", mode="before")
    @classmethod
    def _split_fallbacks(cls, v: object) -> object:
        if isinstance(v, str):
            return [m.strip() for m in v.split(",") if m.strip()]
        return v

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split(cls, v: object) -> object:
        if isinstance(v, str):
            return [o.strip() for o in v.split(",") if o.strip()]
        return v

    @property
    def is_production(self) -> bool:
        return self.env == "production"

    @property
    def ai_configured(self) -> bool:
        return bool(self.ai_api_key)

    def check_production(self) -> None:
        """Refuse to serve production with development secrets."""
        if not self.is_production:
            return
        problems = []
        if self.jwt_secret == DEV_JWT_SECRET:
            problems.append("JWT_SECRET is still the development default")
        if len(self.jwt_secret) < 32:
            problems.append("JWT_SECRET must be at least 32 characters")
        if "*" in self.cors_origins:
            problems.append("CORS_ORIGINS must not be '*'")
        if self.debug:
            problems.append("DEBUG must be false")
        if problems:
            raise RuntimeError("Refusing to start: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
