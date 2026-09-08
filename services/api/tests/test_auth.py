from __future__ import annotations

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
