from __future__ import annotations

import pytest
from httpx import AsyncClient


async def test_register_and_login(client: AsyncClient, registration: dict) -> None:
    r = await client.post("/auth/register", json=registration)
    assert r.status_code == 201, r.text
    assert r.json()["user"]["is_onboarded"] is False

    r = await client.post(
        "/auth/login",
        json={"email": registration["email"], "password": registration["password"]},
    )
    assert r.status_code == 200
    assert r.json()["tokens"]["refresh_token"]


async def test_password_never_echoed(client: AsyncClient, registration: dict) -> None:
    r = await client.post("/auth/register", json=registration)
    assert registration["password"] not in r.text


async def test_email_is_case_insensitive(client: AsyncClient, registration: dict) -> None:
    await client.post("/auth/register", json=registration)
    r = await client.post(
        "/auth/login",
        json={"email": registration["email"].upper(), "password": registration["password"]},
    )
    assert r.status_code == 200


async def test_duplicate_email_conflicts(client: AsyncClient, registration: dict) -> None:
    await client.post("/auth/register", json=registration)
    r = await client.post(
        "/auth/register", json=dict(registration, username=registration["username"] + "x")
    )
    assert r.status_code == 409
    assert r.json()["error"]["details"]["field"] == "email"


async def test_weak_passwords_rejected(client: AsyncClient, registration: dict) -> None:
    assert (
        await client.post("/auth/register", json=dict(registration, password="short"))
    ).status_code == 422
    assert (
        await client.post("/auth/register", json=dict(registration, password="onlyletters"))
    ).status_code == 422


async def test_unknown_email_and_wrong_password_are_identical(
    client: AsyncClient, registration: dict
) -> None:
    """Sign-in must not become an account-enumeration oracle."""
    await client.post("/auth/register", json=registration)
    wrong = await client.post(
        "/auth/login", json={"email": registration["email"], "password": "wrong-pass-9"}
    )
    unknown = await client.post(
        "/auth/login", json={"email": "nobody@example.com", "password": "wrong-pass-9"}
    )
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json()["error"] | {"request_id": ""} == unknown.json()["error"] | {
        "request_id": ""
    }


async def test_refresh_rotates_and_burns_the_old_token(client: AsyncClient, auth: dict) -> None:
    old = auth["tokens"]["refresh_token"]
    r = await client.post("/auth/refresh", json={"refresh_token": old})
    assert r.status_code == 200
    new = r.json()["refresh_token"]
    assert new != old
    assert (await client.post("/auth/refresh", json={"refresh_token": old})).status_code == 401
    assert (await client.post("/auth/refresh", json={"refresh_token": new})).status_code == 200


async def test_logout_revokes(client: AsyncClient, auth: dict) -> None:
    token = auth["tokens"]["refresh_token"]
    assert (await client.post("/auth/logout", json={"refresh_token": token})).status_code == 200
    assert (await client.post("/auth/refresh", json={"refresh_token": token})).status_code == 401
    # Idempotent.
    assert (await client.post("/auth/logout", json={"refresh_token": token})).status_code == 200


async def test_protected_routes_need_a_token(client: AsyncClient) -> None:
    for path in ("/me", "/feed", "/passport", "/projects"):
        r = await client.get(path)
        assert r.status_code == 401, path
        assert r.json()["error"]["code"] in ("UNAUTHORIZED", "TOKEN_INVALID")


async def test_garbage_token_rejected(client: AsyncClient) -> None:
    r = await client.get("/me", headers={"Authorization": "Bearer nope"})
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "TOKEN_INVALID"


async def test_dev_skip_keeps_a_completed_profile(
    client: AsyncClient, seeded: None
) -> None:
    """Skip is a login. Wiping onboarded_at trapped the developer account on
    the questionnaire after the profile had already been filled in."""
    first = await client.post("/auth/dev-skip", json={})
    assert first.status_code == 200, first.text
    headers = {"Authorization": f"Bearer {first.json()['tokens']['access_token']}"}
    onboarded = await client.post(
        "/onboarding",
        headers=headers,
        json={
            "stage": "high",
            "grade": "11",
            "curriculum": "AP",
            "subject_slugs": ["mathematics"],
            "weak_subject_slugs": ["mathematics"],
        },
    )
    assert onboarded.status_code == 200, onboarded.text
    assert onboarded.json()["user"]["is_onboarded"] is True

    again = await client.post("/auth/dev-skip", json={})
    assert again.status_code == 200, again.text
    assert again.json()["user"]["is_onboarded"] is True
    me = await client.get(
        "/me",
        headers={"Authorization": f"Bearer {again.json()['tokens']['access_token']}"},
    )
    assert me.json()["user"]["is_onboarded"] is True
    assert me.json()["profile"]["grade"] == "11"
    assert me.json()["profile"]["weak_subjects"] == ["mathematics"]


async def test_dev_skip_issues_a_real_session(client: AsyncClient) -> None:
    r = await client.post("/auth/dev-skip", json={})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["user"]["email"] == "developer@novi.app"
    assert body["tokens"]["refresh_token"]
    me = await client.get(
        "/me", headers={"Authorization": f"Bearer {body['tokens']['access_token']}"}
    )
    assert me.status_code == 200
    assert me.json()["user"]["email"] == "developer@novi.app"


async def test_dev_skip_is_idempotent(client: AsyncClient) -> None:
    first = await client.post("/auth/dev-skip", json={})
    second = await client.post("/auth/dev-skip", json={})
    assert first.status_code == second.status_code == 200
    assert first.json()["user"]["id"] == second.json()["user"]["id"]


async def test_dev_skip_hidden_in_production(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from novi.config import Settings
    from novi.services import auth_service

    monkeypatch.setattr(
        auth_service,
        "get_settings",
        lambda: Settings(
            env="production",
            jwt_secret="test-secret-value-that-is-long-enough-00000",
        ),
    )
    r = await client.post("/auth/dev-skip", json={})
    assert r.status_code == 404


async def test_dev_skip_requires_secret_when_configured(
    client: AsyncClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from novi.config import Settings
    from novi.services import auth_service

    monkeypatch.setattr(
        auth_service,
        "get_settings",
        lambda: Settings(
            env="test",
            jwt_secret="test-secret-value-that-is-long-enough-00000",
            dev_skip_secret="skip-secret-value",
        ),
    )
    assert (await client.post("/auth/dev-skip", json={})).status_code == 401
    r = await client.post("/auth/dev-skip", json={"secret": "skip-secret-value"})
    assert r.status_code == 200, r.text


def test_production_refuses_dev_skip_secret() -> None:
    from novi.config import Settings

    with pytest.raises(RuntimeError, match="DEV_SKIP_SECRET"):
        Settings(
            env="production",
            jwt_secret="test-secret-value-that-is-long-enough-00000",
            cors_origins=["https://novi.app"],
            debug=False,
            dev_skip_secret="still-set",
        ).check_production()


async def test_health_does_not_advertise_env(client: AsyncClient) -> None:
    r = await client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert "env" not in body
