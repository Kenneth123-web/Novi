"""Test harness.

Runs against a real Postgres (`novi_test`), not SQLite: the schema uses JSONB,
arrays, a tsvector generated column and Postgres full-text search, none of
which SQLite has. A suite that passes on a database the product never runs on
proves very little.

The schema is built by running the *migrations*, so a migration that does not
apply fails the test run rather than the deploy.
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncIterator, Iterator

os.environ.setdefault("DATABASE_URL", "postgresql+asyncpg://novi:novi@localhost:5432/novi_test")
os.environ["ENV"] = "test"
os.environ["JWT_SECRET"] = "test-secret-value-that-is-long-enough-00000"
# Tests must never call the real gateway: it costs money and it makes the suite
# depend on someone else's uptime. Individual tests install a fake.
os.environ["AI_API_KEY"] = ""
# Hermetic Turnstile: register/login still require a token. The verifier is
# monkeypatched below so tests never call Cloudflare. The dummy token is
# Cloudflare's documented test value.
os.environ.setdefault("TURNSTILE_SITEKEY", "1x00000000000000000000AA")
os.environ.setdefault("TURNSTILE_SITEVERIFY_URL", "https://turnstile.test/siteverify")

import pytest
from alembic import command
from alembic.config import Config
from httpx import ASGITransport, AsyncClient
from sqlalchemy import text

from novi.config import get_settings
from novi.db import dispose_engine, get_sessionmaker
from novi.main import create_app

TEST_TURNSTILE_TOKEN = "XXXX.DUMMY.TOKEN"

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

TABLES = (
    "users, subjects, concepts, concept_edges, content, content_concepts, "
    "discussions, discussion_comments, interactions, saved_content, content_likes, "
    "learning_progress, questions, ai_responses, quizzes, quiz_questions, "
    "quiz_results, passport_stamps, projects, project_concepts"
)


@pytest.fixture(scope="session", autouse=True)
def migrated_database() -> Iterator[None]:
    get_settings.cache_clear()
    cfg = Config(os.path.join(REPO_ROOT, "database", "alembic.ini"))
    cfg.set_main_option("script_location", os.path.join(REPO_ROOT, "database", "migrations"))
    command.downgrade(cfg, "base")
    command.upgrade(cfg, "head")
    yield


@pytest.fixture(autouse=True)
async def clean_tables() -> AsyncIterator[None]:
    """Truncate between tests rather than wrap them in a transaction.

    The app's `get_db` dependency commits, so a wrapping transaction would have
    to be nested to survive it — and the test would then be exercising a commit
    path the production code never takes.
    """
    yield
    async with get_sessionmaker()() as db:
        await db.execute(text(f"TRUNCATE {TABLES} RESTART IDENTITY CASCADE"))
        await db.commit()


@pytest.fixture(scope="session", autouse=True)
async def _dispose() -> AsyncIterator[None]:
    yield
    await dispose_engine()


@pytest.fixture
async def client() -> AsyncIterator[AsyncClient]:
    app = create_app()
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test/v1"
    ) as ac:
        yield ac


@pytest.fixture
def registration() -> dict[str, str]:
    handle = uuid.uuid4().hex[:10]
    return {
        "email": f"student-{handle}@example.com",
        "username": f"student_{handle}",
        "password": "correct-horse-7",
        "display_name": "Test Student",
        "turnstile_token": TEST_TURNSTILE_TOKEN,
    }


@pytest.fixture(autouse=True)
def stub_turnstile(monkeypatch: pytest.MonkeyPatch) -> None:
    """Accept Cloudflare's dummy token; reject anything else. Fail closed."""
    from novi.core.errors import APIError, Forbidden
    from novi.services import turnstile

    async def _fake(token: str, *, remote_ip: str | None = None) -> None:
        del remote_ip
        token = (token or "").strip()
        if not token:
            raise APIError(
                "Complete the CAPTCHA and try again",
                code="CAPTCHA_REQUIRED",
                status_code=400,
                details={"field": "turnstile_token"},
            )
        if token == TEST_TURNSTILE_TOKEN:
            return
        raise Forbidden(
            "CAPTCHA verification failed",
            code="CAPTCHA_FAILED",
            details={"field": "turnstile_token"},
        )

    monkeypatch.setattr(turnstile, "verify_turnstile", _fake)


@pytest.fixture
async def auth(client: AsyncClient, registration: dict[str, str]) -> dict:
    r = await client.post("/auth/register", json=registration)
    assert r.status_code == 201, r.text
    body = r.json()
    return {
        "user": body["user"],
        "tokens": body["tokens"],
        "headers": {"Authorization": f"Bearer {body['tokens']['access_token']}"},
        "credentials": registration,
    }


@pytest.fixture
async def seeded() -> AsyncIterator[None]:
    import sys

    if REPO_ROOT not in sys.path:
        sys.path.insert(0, REPO_ROOT)
    from database.seeds.seed import seed

    await seed()
    yield


@pytest.fixture
async def onboarded(client: AsyncClient, auth: dict, seeded: None) -> dict:
    r = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={
            "stage": "high",
            "grade": "11",
            "curriculum": "AP",
            "subject_slugs": ["mathematics", "computer-science"],
            "weak_subject_slugs": ["mathematics"],
            "learning_preferences": ["short_video", "visual"],
            "goals": ["exam_prep"],
        },
    )
    assert r.status_code == 200, r.text
    return auth
