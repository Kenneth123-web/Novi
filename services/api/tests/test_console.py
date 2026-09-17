from __future__ import annotations

import asyncio
import time

import httpx
import pytest
import respx
from httpx import AsyncClient

from novi.config import get_settings


@pytest.fixture
def console_origin(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("CONSOLE_BASE_URL", "https://console.test")
    monkeypatch.setenv("CONSOLE_ORIGIN_SECRET", "origin-secret")
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@respx.mock
async def test_register_ingests_account(
    client: AsyncClient, registration: dict, console_origin: None
) -> None:
    route = respx.post("https://console.test/api/ingest/account").mock(
        return_value=httpx.Response(204)
    )
    r = await client.post("/auth/register", json=registration)
    assert r.status_code == 201, r.text
    for _ in range(40):
        if route.called:
            break
        await asyncio.sleep(0.05)
    assert route.called
    payload = route.calls.last.request.content
    assert registration["email"].encode() in payload
    assert b"registered" in payload


@respx.mock
async def test_login_checks_console_status(
    client: AsyncClient, registration: dict, console_origin: None
) -> None:
    respx.post("https://console.test/api/ingest/account").mock(
        return_value=httpx.Response(204)
    )
    created = await client.post("/auth/register", json=registration)
    user_id = created.json()["user"]["id"]
    status = respx.get(f"https://console.test/api/ingest/status/{user_id}").mock(
        return_value=httpx.Response(200, json={"is_active": False})
    )
    r = await client.post(
        "/auth/login",
        json={
            "email": registration["email"],
            "password": registration["password"],
            "turnstile_token": registration["turnstile_token"],
        },
    )
    assert status.called
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "INVALID_CREDENTIALS"


@respx.mock
async def test_console_outage_does_not_block_login(
    client: AsyncClient, registration: dict, console_origin: None
) -> None:
    respx.post("https://console.test/api/ingest/account").mock(
        return_value=httpx.Response(204)
    )
    created = await client.post("/auth/register", json=registration)
    user_id = created.json()["user"]["id"]
    respx.get(f"https://console.test/api/ingest/status/{user_id}").mock(
        side_effect=httpx.ConnectError("down")
    )
    r = await client.post(
        "/auth/login",
        json={
            "email": registration["email"],
            "password": registration["password"],
            "turnstile_token": registration["turnstile_token"],
        },
    )
    assert r.status_code == 200


@respx.mock
async def test_internal_disable_revokes_sessions(
    client: AsyncClient, auth: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CONSOLE_ORIGIN_SECRET", "origin-secret")
    get_settings.cache_clear()
    user_id = auth["user"]["id"]
    r = await client.patch(
        f"/internal/users/{user_id}",
        json={"is_active": False},
        headers={"X-Novi-Origin-Secret": "origin-secret"},
    )
    assert r.status_code == 200, r.text
    me = await client.get("/me", headers=auth["headers"])
    assert me.status_code == 401
    get_settings.cache_clear()


async def test_internal_without_secret_is_absent(
    client: AsyncClient, auth: dict, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("CONSOLE_ORIGIN_SECRET", "")
    get_settings.cache_clear()
    r = await client.patch(
        f"/internal/users/{auth['user']['id']}",
        json={"is_active": False},
    )
    assert r.status_code == 404
    get_settings.cache_clear()


@respx.mock
async def test_dev_skip_caps_a_hung_console_status(
    client: AsyncClient, console_origin: None
) -> None:
    async def hang(_request: httpx.Request) -> httpx.Response:
        await asyncio.sleep(30)
        return httpx.Response(200, json={"is_active": True})

    respx.get(url__regex=r"https://console\.test/api/ingest/status/.*").mock(side_effect=hang)
    respx.post("https://console.test/api/ingest/account").mock(
        return_value=httpx.Response(204)
    )
    started = time.perf_counter()
    r = await client.post("/auth/dev-skip", json={})
    assert r.status_code == 200, r.text
    assert time.perf_counter() - started < 5
