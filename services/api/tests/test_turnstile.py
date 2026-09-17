from __future__ import annotations

import httpx
import pytest
import respx
from httpx import AsyncClient

from novi.config import Settings, get_settings
from novi.services import turnstile
from novi.services.turnstile import CLOUDFLARE_DUMMY_TOKEN, verify_turnstile


@pytest.fixture
def real_turnstile(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(turnstile, "verify_turnstile", verify_turnstile)
    yield
    get_settings.cache_clear()


async def test_register_without_token_is_rejected(
    client: AsyncClient, registration: dict
) -> None:
    body = dict(registration)
    body.pop("turnstile_token")
    r = await client.post("/auth/register", json=body)
    assert r.status_code == 400, r.text
    assert r.json()["error"]["code"] == "CAPTCHA_REQUIRED"


async def test_login_without_token_is_rejected(
    client: AsyncClient, registration: dict
) -> None:
    await client.post("/auth/register", json=registration)
    r = await client.post(
        "/auth/login",
        json={"email": registration["email"], "password": registration["password"]},
    )
    assert r.status_code == 400, r.text
    assert r.json()["error"]["code"] == "CAPTCHA_REQUIRED"


async def test_register_invalid_token_is_rejected(
    client: AsyncClient, registration: dict
) -> None:
    r = await client.post(
        "/auth/register", json=dict(registration, turnstile_token="not-a-real-token")
    )
    assert r.status_code == 403, r.text
    assert r.json()["error"]["code"] == "CAPTCHA_FAILED"


async def test_login_invalid_token_is_rejected(
    client: AsyncClient, registration: dict
) -> None:
    await client.post("/auth/register", json=registration)
    r = await client.post(
        "/auth/login",
        json={
            "email": registration["email"],
            "password": registration["password"],
            "turnstile_token": "not-a-real-token",
        },
    )
    assert r.status_code == 403, r.text
    assert r.json()["error"]["code"] == "CAPTCHA_FAILED"


async def test_register_and_login_accept_valid_token(
    client: AsyncClient, registration: dict
) -> None:
    created = await client.post("/auth/register", json=registration)
    assert created.status_code == 201, created.text
    logged = await client.post(
        "/auth/login",
        json={
            "email": registration["email"],
            "password": registration["password"],
            "turnstile_token": registration["turnstile_token"],
        },
    )
    assert logged.status_code == 200, logged.text


async def test_dev_skip_does_not_require_turnstile(client: AsyncClient) -> None:
    r = await client.post("/auth/dev-skip", json={})
    assert r.status_code == 200, r.text


async def test_captcha_config_is_public(client: AsyncClient) -> None:
    r = await client.get("/auth/captcha")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["provider"] == "turnstile"
    assert body["enabled"] is True
    assert body["sitekey"]
    assert body["action"] == "turnstile-spin-v1"


@respx.mock
async def test_http_verifier_accepts_worker_success(
    client: AsyncClient, registration: dict, real_turnstile: None
) -> None:
    route = respx.post("https://turnstile.test/siteverify").mock(
        return_value=httpx.Response(200, json={"success": True, "error-codes": []})
    )
    r = await client.post("/auth/register", json=registration)
    assert r.status_code == 201, r.text
    assert route.called
    sent = route.calls.last.request
    assert CLOUDFLARE_DUMMY_TOKEN.encode() in sent.content


@respx.mock
async def test_http_verifier_rejects_worker_failure(
    client: AsyncClient, registration: dict, real_turnstile: None
) -> None:
    respx.post("https://turnstile.test/siteverify").mock(
        return_value=httpx.Response(
            200, json={"success": False, "error-codes": ["invalid-input-response"]}
        )
    )
    r = await client.post("/auth/register", json=registration)
    assert r.status_code == 403, r.text
    assert r.json()["error"]["code"] == "CAPTCHA_FAILED"


@respx.mock
async def test_http_verifier_fails_closed_when_worker_is_down(
    client: AsyncClient, registration: dict, real_turnstile: None
) -> None:
    respx.post("https://turnstile.test/siteverify").mock(
        side_effect=httpx.ConnectError("down")
    )
    r = await client.post("/auth/register", json=registration)
    assert r.status_code == 503, r.text
    assert r.json()["error"]["code"] == "CAPTCHA_UNAVAILABLE"


async def test_dummy_token_only_when_siteverify_url_is_unset(
    monkeypatch: pytest.MonkeyPatch, real_turnstile: None
) -> None:
    monkeypatch.setenv("TURNSTILE_SITEVERIFY_URL", "")
    monkeypatch.setenv("ENV", "development")
    get_settings.cache_clear()
    await verify_turnstile(CLOUDFLARE_DUMMY_TOKEN)
    with pytest.raises(Exception) as failed:
        await verify_turnstile("forged-token")
    assert getattr(failed.value, "code", "") == "CAPTCHA_FAILED"


def test_production_refuses_missing_turnstile() -> None:
    with pytest.raises(RuntimeError, match="TURNSTILE_SITEVERIFY_URL"):
        Settings(
            env="production",
            jwt_secret="test-secret-value-that-is-long-enough-00000",
            cors_origins=["https://novi.app"],
            debug=False,
            turnstile_sitekey="0x4AAAAAAE5j-PpNPgTtBBtz",
            turnstile_siteverify_url="",
        ).check_production()


def test_production_accepts_configured_turnstile() -> None:
    Settings(
        env="production",
        jwt_secret="test-secret-value-that-is-long-enough-00000",
        cors_origins=["https://novi.app"],
        debug=False,
        turnstile_sitekey="0x4AAAAAAE5j-PpNPgTtBBtz",
        turnstile_siteverify_url="https://turnstile-siteverify-novi.example.workers.dev",
    ).check_production()
