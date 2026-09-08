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
    ai_model: str = "gemini-3.5-flash"
    ai_model_fast: str = "gemini-2.5-flash"
    ai_timeout_seconds: float = 60.0
    ai_max_output_tokens: int = 2048

    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

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
