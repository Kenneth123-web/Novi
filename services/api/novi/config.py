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
    # Short-lived on purpose. Logout only burns the refresh row; a stolen
    # access JWT stays valid until exp. Seven days made theft durable.
    # The iOS client already refreshes on 401, so an hour is enough.
    access_token_ttl_seconds: int = 60 * 60
    refresh_token_ttl_seconds: int = 60 * 60 * 24 * 60

    # Developer skip-login. Empty means the route exists in development/test
    # and is absent in production. A non-empty value must be presented as
    # `secret` on POST /auth/dev-skip, in every environment.
    dev_skip_secret: str = ""

    # Cloudflare Turnstile. The sitekey is public (iOS + console widget).
    # Siteverify goes through the managed Worker; the secret never lives here.
    # In development/test an empty URL accepts only Cloudflare's dummy token
    # `XXXX.DUMMY.TOKEN`. Production refuses to boot without both values.
    turnstile_sitekey: str = ""
    turnstile_siteverify_url: str = ""
    turnstile_widget_url: str = ""

    # ── Console (Cloudflare Worker that stores accounts + API usage) ─────────
    # Empty CONSOLE_BASE_URL disables ingest: local tests and a fresh clone
    # must not depend on Cloudflare being up. The origin secret is what the
    # Worker checks before accepting a write.
    console_base_url: str = ""
    console_origin_secret: str = ""

    # ── AI gateway (OpenAI-compatible, in front of Gemini) ───────────────────
    ai_base_url: str = "https://1pkapi.com/v1"
    ai_api_key: str | None = None

    # Which wire protocol the gateway speaks.
    #
    # "openai" is POST /v1/chat/completions with a bearer token; "anthropic" is
    # POST /v1/messages with x-api-key. Which one is right depends entirely on
    # what the gateway is fronting — Grok answers on the OpenAI path and
    # returns "Service temporarily unavailable" on the Anthropic one, and the
    # Claude roster was the other way round. Hence a setting rather than a
    # hardcoded client.
    ai_protocol: Literal["anthropic", "openai"] = "openai"

    # Grok. Of the nine models this gateway lists, grok-4.6 and grok-4.5 are
    # the two that actually answer; the rest return "Upstream request failed".
    # The chain below is ordered by what was measured, not by what is listed.
    ai_model: str = "grok-4.6"
    ai_model_fast: str = "grok-4.5"
    ai_model_fallbacks: list[str] = Field(
        default_factory=lambda: ["grok-4.5", "grok-4.6", "grok-4.3"]
    )
    # A ceiling for the bad tail, not the expected wait. Measured against this
    # gateway a full explanation lands in 6-31s, but the variance is wide and
    # 45s — tuned back when the gateway only ever failed — cut off real
    # generations.
    #
    # Still deliberately shorter than the client's, so the server loses that
    # race on purpose: whichever side times out first decides what the learner
    # reads, and the server's structured AI_UNAVAILABLE says more than the
    # client's generic transport error.
    ai_timeout_seconds: float = 140.0
    ai_max_output_tokens: int = 2048

    cors_origins: list[str] = Field(default_factory=lambda: ["*"])

    youtube_api_key: str | None = None
    x_bearer_token: str | None = None
    # Directory of JSON/JSONL dumps from https://github.com/NanmiCoder/MediaCrawler.
    # Live Bilibili search runs without this; cookie-gated platforms (XHS, Douyin)
    # land here after a MediaCrawler run.
    mediacrawler_data_dir: str = ""

    @field_validator("ai_model_fallbacks", mode="before")
    @classmethod
    def _split_fallbacks(cls, v: object) -> object:
        if isinstance(v, str):
            return [m.strip() for m in v.split(",") if m.strip()]
        return v

    @field_validator("ai_timeout_seconds", mode="before")
    @classmethod
    def _empty_timeout(cls, v: object) -> object:
        if v == "" or v is None:
            return 140.0
        return v

    @field_validator("ai_api_key", "youtube_api_key", "x_bearer_token", mode="before")
    @classmethod
    def _empty_secret(cls, v: object) -> object:
        if isinstance(v, str) and not v.strip():
            return None
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
        if self.dev_skip_secret:
            problems.append("DEV_SKIP_SECRET must be unset in production")
        if self.console_base_url and len(self.console_origin_secret) < 32:
            problems.append(
                "CONSOLE_ORIGIN_SECRET must be at least 32 characters when CONSOLE_BASE_URL is set"
            )
        if not self.turnstile_sitekey.strip():
            problems.append("TURNSTILE_SITEKEY must be set")
        if not self.turnstile_siteverify_url.strip():
            problems.append("TURNSTILE_SITEVERIFY_URL must be set")
        if problems:
            raise RuntimeError("Refusing to start: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
