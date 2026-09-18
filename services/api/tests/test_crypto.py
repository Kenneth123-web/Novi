"""At-rest encryption is dual-read and invisible on the HTTP surface."""

from __future__ import annotations

from httpx import AsyncClient
from sqlalchemy import text

from novi.core.crypto import PREFIX, decrypt_text, encrypt_text, is_envelope
from novi.db import get_sessionmaker
from novi.services.auth_service import DEV_SKIP_EMAIL, DEV_SKIP_USERNAME


def test_envelope_round_trip() -> None:
    sealed = encrypt_text("a learner question")
    assert is_envelope(sealed)
    assert sealed.startswith(PREFIX)
    assert "learner" not in sealed
    assert decrypt_text(sealed) == "a learner question"


def test_plaintext_that_predates_encryption_is_returned() -> None:
    assert decrypt_text("Why does a derivative represent slope?") == (
        "Why does a derivative represent slope?"
    )


def test_empty_values_are_not_sealed() -> None:
    assert encrypt_text("") == ""
    assert decrypt_text("") == ""


async def test_reserved_developer_identity_cannot_be_registered(
    client: AsyncClient, registration: dict
) -> None:
    taken_email = await client.post(
        "/auth/register",
        json=dict(registration, email=DEV_SKIP_EMAIL, username="someone_else"),
    )
    assert taken_email.status_code == 409
    assert taken_email.json()["error"]["details"]["field"] == "email"

    taken_name = await client.post(
        "/auth/register",
        json=dict(registration, username=DEV_SKIP_USERNAME),
    )
    assert taken_name.status_code == 409
    assert taken_name.json()["error"]["details"]["field"] == "username"


async def test_security_headers_are_present(client: AsyncClient) -> None:
    r = await client.get("/health")
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["x-frame-options"] == "DENY"


async def test_question_and_answer_are_sealed_in_postgres(
    client: AsyncClient, auth: dict, monkeypatch
) -> None:
    from novi.ai.gateway import AIResult, gateway

    async def _complete(**kwargs: object) -> AIResult:
        return AIResult(
            data={"summary": "slope", "simple_explanation": "zoom in"},
            model="fake-model",
            input_tokens=1,
            output_tokens=1,
        )

    monkeypatch.setattr(gateway, "complete_json", _complete)
    asked = "Why does a derivative represent slope?"
    r = await client.post("/ask", headers=auth["headers"], json={"question": asked})
    assert r.status_code == 200, r.text

    async with get_sessionmaker()() as db:
        stored_text = (await db.execute(text("SELECT text FROM questions"))).scalar_one()
        stored_payload = (await db.execute(text("SELECT payload FROM ai_responses"))).scalar_one()

    assert isinstance(stored_text, str) and stored_text.startswith(PREFIX)
    assert asked not in stored_text
    assert isinstance(stored_payload, dict) and PREFIX in str(stored_payload.get("_nv1", ""))
    assert "zoom in" not in str(stored_payload)

    history = await client.get("/questions", headers=auth["headers"])
    assert history.status_code == 200
    assert history.json()[0]["text"] == asked
    assert history.json()[0]["answer"]["summary"] == "slope"
