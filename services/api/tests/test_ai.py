"""The AI paths.

Nothing here touches the real gateway: it costs money per call and it would
make the suite depend on someone else's uptime. The gateway's own request and
error handling is tested against a mocked transport; everything above it is
tested against a stubbed `complete_json`.
"""

from __future__ import annotations

import json
from typing import Any

import httpx
import pytest
import respx
from httpx import AsyncClient

from novi.ai.gateway import AIGateway, AIResult, gateway
from novi.config import get_settings
from novi.core.errors import AIUnavailable

EXPLANATION = {
    "concept": "Derivatives",
    "summary": "A derivative is the slope of a curve at a single point.",
    "simple_explanation": "Zoom in far enough on a smooth curve and it looks straight.",
    "why_it_works": "The limit of the average rate of change as the interval shrinks.",
    "example": "For f(x) = x^2, the slope at x = 3 is 6.",
    "common_misconception": "That a derivative is a fraction you can split apart.",
    "related_concepts": ["Limits", "The Chain Rule", "Integrals"],
    "search_queries": ["derivatives slope", "derivative intuition"],
}


@pytest.fixture
def fake_ai(monkeypatch: pytest.MonkeyPatch):
    """Replace the model call, keeping every layer above it real."""

    def install(payload: dict[str, Any]) -> list[dict]:
        calls: list[dict] = []

        async def _complete(**kwargs: Any) -> AIResult:
            calls.append(kwargs)
            return AIResult(data=payload, model="fake-model", input_tokens=10, output_tokens=20)

        monkeypatch.setattr(gateway, "complete_json", _complete)
        return calls

    return install


# ── Gateway transport ────────────────────────────────────────────────────────
#
# The protocol is a setting because it has to be: Grok answers on the OpenAI
# path and refuses the Anthropic one, and the Claude roster was the other way
# round. Both paths are covered, because picking the wrong one is silent — the
# request just fails in a way that looks like an outage.


def _url(protocol: str) -> str:
    base = get_settings().ai_base_url.rstrip("/")
    return f"{base}/messages" if protocol == "anthropic" else f"{base}/chat/completions"


def _reply(protocol: str, text: str) -> dict:
    """A success body in whichever shape the protocol returns."""
    if protocol == "anthropic":
        return {
            "content": [{"type": "text", "text": text}],
            "usage": {"input_tokens": 5, "output_tokens": 3},
        }
    return {
        "choices": [{"message": {"role": "assistant", "content": text}}],
        "usage": {"prompt_tokens": 5, "completion_tokens": 3},
    }


def _error(kind: str, message: str) -> dict:
    return {"type": "error", "error": {"type": kind, "message": message}}


@pytest.fixture
def configured(monkeypatch: pytest.MonkeyPatch):
    """Set the key and a protocol, and clear the settings cache either side."""

    def install(protocol: str = "openai") -> str:
        monkeypatch.setenv("AI_API_KEY", "test-key")
        monkeypatch.setenv("AI_PROTOCOL", protocol)
        get_settings.cache_clear()
        return protocol

    yield install
    get_settings.cache_clear()


@pytest.mark.parametrize("protocol", ["openai", "anthropic"])
@respx.mock
async def test_gateway_reads_either_protocols_reply(configured, protocol: str) -> None:
    configured(protocol)
    respx.post(_url(protocol)).mock(
        return_value=httpx.Response(200, json=_reply(protocol, '{"summary": "ok"}'))
    )

    result = await AIGateway().complete_json(system="s", user="u")

    assert result.data == {"summary": "ok"}
    assert result.input_tokens == 5
    assert result.output_tokens == 3


@respx.mock
async def test_openai_path_sends_system_as_a_message(configured) -> None:
    configured("openai")
    route = respx.post(_url("openai")).mock(
        return_value=httpx.Response(200, json=_reply("openai", "{}"))
    )

    await AIGateway().complete_json(system="RULES", user="question")

    sent = json.loads(route.calls.last.request.content)
    assert sent["messages"][0] == {"role": "system", "content": "RULES"}
    assert route.calls.last.request.headers["authorization"] == "Bearer test-key"


@respx.mock
async def test_anthropic_path_sends_system_at_the_top_level(configured) -> None:
    """Passed as a message it is accepted and silently ignored — no error, and
    the model never sees the rules it was supposed to follow."""
    configured("anthropic")
    route = respx.post(_url("anthropic")).mock(
        return_value=httpx.Response(200, json=_reply("anthropic", "{}"))
    )

    await AIGateway().complete_json(system="RULES", user="question")

    sent = json.loads(route.calls.last.request.content)
    assert sent["system"] == "RULES"
    assert sent["messages"] == [{"role": "user", "content": "question"}]
    assert route.calls.last.request.headers["x-api-key"] == "test-key"
    assert route.calls.last.request.headers["anthropic-version"] == "2023-06-01"


@respx.mock
async def test_gateway_maps_capacity_errors_to_ai_unavailable(configured) -> None:
    """Must surface as AI_UNAVAILABLE, not a 500: the app shows a "tutor is
    unavailable" state and stays usable, rather than looking broken."""
    configured("openai")
    respx.post(_url("openai")).mock(
        return_value=httpx.Response(
            200, json=_error("rate_limit_error", "Upstream rate limit exceeded")
        )
    )

    with pytest.raises(AIUnavailable) as exc:
        await AIGateway().complete_json(system="s", user="u")

    assert exc.value.code == "AI_UNAVAILABLE"
    assert exc.value.details["reason"] == "capacity"
    # The upstream text is kept for the log, not for the student.
    assert "rate limit" in exc.value.details["upstream"].lower()


@respx.mock
async def test_gateway_falls_through_to_a_model_that_works(configured) -> None:
    """This gateway lists nine Grok models and serves two.

    "Upstream request failed" is how it reports the other seven, so it has to
    move the chain along — but it is also what a real blip looks like.
    """
    configured("openai")
    monkey_models = ["grok-4.3", "grok-4.6"]
    seen: list[str] = []

    def responder(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        seen.append(model)
        if model != "grok-4.6":
            return httpx.Response(200, json=_error("upstream_error", "Upstream request failed"))
        return httpx.Response(200, json=_reply("openai", '{"summary": "fell through"}'))

    respx.post(_url("openai")).mock(side_effect=responder)

    result = await AIGateway().complete_json(system="s", user="u", model=monkey_models[0])

    assert seen[0] == "grok-4.3"
    assert result.model == "grok-4.6"
    assert result.data["summary"] == "fell through"


@respx.mock
async def test_a_model_the_account_lacks_is_not_retried_next_call(configured) -> None:
    """`model_not_found` is a fact about the account, so it is remembered —
    otherwise every request pays for the same rejection again."""
    configured("openai")
    seen: list[str] = []

    def responder(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        seen.append(model)
        if model == "ghost-model":
            return httpx.Response(200, json=_error("model_not_found", "no such model"))
        return httpx.Response(200, json=_reply("openai", "{}"))

    respx.post(_url("openai")).mock(side_effect=responder)

    client = AIGateway()
    await client.complete_json(system="s", user="u", model="ghost-model")
    seen.clear()
    await client.complete_json(system="s", user="u", model="ghost-model")

    assert "ghost-model" not in seen


@respx.mock
async def test_a_transient_upstream_failure_is_not_remembered(configured) -> None:
    """The opposite case. Blacklisting a working model over one blip would
    quietly drop the best model out of the chain for the whole process."""
    configured("openai")
    calls = {"n": 0}

    def responder(request: httpx.Request) -> httpx.Response:
        model = json.loads(request.content)["model"]
        if model == "flaky" and calls["n"] == 0:
            calls["n"] += 1
            return httpx.Response(200, json=_error("upstream_error", "Upstream request failed"))
        return httpx.Response(200, json=_reply("openai", '{"summary": "recovered"}'))

    respx.post(_url("openai")).mock(side_effect=responder)

    client = AIGateway()
    await client.complete_json(system="s", user="u", model="flaky")
    second = await client.complete_json(system="s", user="u", model="flaky")

    assert second.model == "flaky"


@respx.mock
async def test_gateway_unwraps_a_json_code_fence(configured) -> None:
    """Models wrap JSON in ``` fences even when told not to."""
    configured("openai")
    respx.post(_url("openai")).mock(
        return_value=httpx.Response(
            200, json=_reply("openai", '```json\n{"summary": "ok"}\n```')
        )
    )

    result = await AIGateway().complete_json(system="s", user="u")
    assert result.data == {"summary": "ok"}


async def test_gateway_without_a_key_is_unavailable_not_a_crash() -> None:
    get_settings.cache_clear()
    with pytest.raises(AIUnavailable) as exc:
        await AIGateway().complete_json(system="s", user="u")
    assert exc.value.details["reason"] == "missing_api_key"


async def test_ask_returns_503_when_the_tutor_is_down(
    client: AsyncClient, onboarded: dict
) -> None:
    """No key is configured in tests, so this is the real unconfigured path."""
    r = await client.post(
        "/ask", headers=onboarded["headers"], json={"question": "Why is the sky blue?"}
    )
    assert r.status_code == 503
    assert r.json()["error"]["code"] == "AI_UNAVAILABLE"
    assert r.json()["error"]["request_id"]


# ── Ask ──────────────────────────────────────────────────────────────────────


async def test_ask_returns_an_explanation_and_a_discovery_rail(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    fake_ai(EXPLANATION)
    r = await client.post(
        "/ask",
        headers=onboarded["headers"],
        json={"question": "Why does a derivative represent slope?"},
    )
    assert r.status_code == 200, r.text
    body = r.json()

    assert body["explanation"]["summary"] == EXPLANATION["summary"]
    # The page must not end when the explanation does.
    assert body["watch"] or body["read"], "the rabbit hole must have something in it"
    assert body["related_concepts"], "related concepts drive the next hop"
    # A related concept that exists in our graph is resolved to a tappable id.
    assert any(c["id"] for c in body["related_concepts"])


async def test_ask_sends_the_students_context_to_the_model(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    calls = fake_ai(EXPLANATION)
    await client.post(
        "/ask", headers=onboarded["headers"], json={"question": "Explain limits", "mode": "eli10"}
    )
    prompt = calls[0]["user"]
    assert "Explain limits" in prompt
    assert "high school student" in prompt
    assert "AP" in prompt
    assert "10-year-old" in prompt


async def test_ask_rejects_an_unknown_mode(client: AsyncClient, onboarded: dict) -> None:
    r = await client.post(
        "/ask", headers=onboarded["headers"], json={"question": "hi there", "mode": "interpretive"}
    )
    assert r.status_code == 422
    assert r.json()["error"]["details"]["field"] == "mode"


async def test_asking_records_the_question_and_moves_the_knowledge_model(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    fake_ai(EXPLANATION)
    concepts = await client.get("/concepts", params={"subject_slug": "mathematics"})
    derivatives = next(c for c in concepts.json() if c["slug"] == "derivatives")

    await client.post(
        "/ask",
        headers=onboarded["headers"],
        json={"question": "Explain derivatives", "concept_id": derivatives["id"]},
    )

    history = await client.get("/questions", headers=onboarded["headers"])
    assert history.json()[0]["text"] == "Explain derivatives"

    passport = await client.get("/passport", headers=onboarded["headers"])
    touched = [
        c
        for card in passport.json()["subject_cards"]
        for c in card["concepts"]
        if c["slug"] == "derivatives"
    ]
    assert touched and touched[0]["mastery"] == "explored"


# ── Quiz ─────────────────────────────────────────────────────────────────────

QUIZ = {
    "questions": [
        {
            "prompt": f"Question {i}?",
            "options": [f"a{i}", f"b{i}", f"c{i}", f"d{i}"],
            "correct_index": i % 4,
            "explanation": f"Because {i}.",
        }
        for i in range(4)
    ]
}


async def _derivatives_id(client: AsyncClient) -> str:
    concepts = await client.get("/concepts", params={"subject_slug": "mathematics"})
    return next(c for c in concepts.json() if c["slug"] == "derivatives")["id"]


async def test_quiz_never_ships_the_answer_key(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    fake_ai(QUIZ)
    concept_id = await _derivatives_id(client)
    r = await client.post(
        "/quiz", headers=onboarded["headers"], json={"concept_id": concept_id, "count": 4}
    )
    assert r.status_code == 200, r.text
    assert "correct_index" not in r.text
    assert len(r.json()["questions"]) == 4


async def test_quiz_grades_and_updates_mastery_and_stamps(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    fake_ai(QUIZ)
    concept_id = await _derivatives_id(client)
    quiz = (
        await client.post(
            "/quiz", headers=onboarded["headers"], json={"concept_id": concept_id, "count": 4}
        )
    ).json()

    # Answer everything correctly: ordinal i has correct_index i % 4.
    answers = [
        {"question_id": q["id"], "selected_index": q["ordinal"] % 4} for q in quiz["questions"]
    ]
    r = await client.post(
        f"/quiz/{quiz['id']}/submit", headers=onboarded["headers"], json={"answers": answers}
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["score"] == 1.0
    assert body["correct"] == 4
    assert body["concept_mastery"] == "learned"
    # The key is revealed only now, with the grading.
    assert all("correct_index" in a for a in body["answers"])
    assert any(s["kind"] == "concept" for s in body["new_stamps"])


async def test_unanswered_questions_count_as_wrong(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    """Otherwise a learner masters a concept by answering one question."""
    fake_ai(QUIZ)
    concept_id = await _derivatives_id(client)
    quiz = (
        await client.post(
            "/quiz", headers=onboarded["headers"], json={"concept_id": concept_id, "count": 4}
        )
    ).json()

    one = quiz["questions"][0]
    r = await client.post(
        f"/quiz/{quiz['id']}/submit",
        headers=onboarded["headers"],
        json={"answers": [{"question_id": one["id"], "selected_index": one["ordinal"] % 4}]},
    )
    assert r.json()["score"] == 0.25
    assert r.json()["concept_mastery"] == "practiced"


async def test_a_quiz_cannot_be_submitted_twice(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    fake_ai(QUIZ)
    concept_id = await _derivatives_id(client)
    quiz = (
        await client.post(
            "/quiz", headers=onboarded["headers"], json={"concept_id": concept_id, "count": 4}
        )
    ).json()
    answers = [{"question_id": q["id"], "selected_index": 0} for q in quiz["questions"]]

    first = await client.post(
        f"/quiz/{quiz['id']}/submit", headers=onboarded["headers"], json={"answers": answers}
    )
    assert first.status_code == 200
    second = await client.post(
        f"/quiz/{quiz['id']}/submit", headers=onboarded["headers"], json={"answers": answers}
    )
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "ALREADY_SUBMITTED"


async def test_a_malformed_quiz_is_rejected_not_stored(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    """Three options, or two correct answers, would mark a right answer wrong."""
    fake_ai(
        {
            "questions": [
                {"prompt": "q", "options": ["a", "b", "c"], "correct_index": 0, "explanation": ""},
                {"prompt": "q", "options": ["a", "a", "b", "c"], "correct_index": 9,
                 "explanation": ""},
            ]
        }
    )
    concept_id = await _derivatives_id(client)
    r = await client.post(
        "/quiz", headers=onboarded["headers"], json={"concept_id": concept_id, "count": 4}
    )
    assert r.status_code == 503
    assert r.json()["error"]["details"]["reason"] == "too_few_valid"


# ── Discussions ──────────────────────────────────────────────────────────────


async def test_discussion_summary_is_cached_after_the_first_call(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    calls = fake_ai({"main_ideas": ["one", "two"], "agreement": [], "disagreement": []})
    listing = await client.get("/discussions", headers=onboarded["headers"], params={"limit": 1})
    discussion_id = listing.json()[0]["id"]

    first = await client.post(
        f"/discussions/{discussion_id}/summarize", headers=onboarded["headers"]
    )
    assert first.status_code == 200
    assert first.json()["main_ideas"] == ["one", "two"]

    second = await client.post(
        f"/discussions/{discussion_id}/summarize", headers=onboarded["headers"]
    )
    assert second.status_code == 200
    # Summarising is one of the two most expensive calls in the product and the
    # thread does not change; paying twice is paying twice for the same bytes.
    assert len(calls) == 1


async def test_translation_is_noop_when_already_in_target_language(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    """iOS asks for 'English'; the store tags threads as 'en'."""
    calls = fake_ai({"title": "T", "body": "B", "comments": []})
    listing = await client.get("/discussions", headers=onboarded["headers"], params={"limit": 1})
    discussion_id = listing.json()[0]["id"]

    r = await client.post(
        f"/discussions/{discussion_id}/translate",
        headers=onboarded["headers"],
        json={"translate_to": "English"},
    )
    assert r.status_code == 200, r.text
    assert r.json().get("unchanged") is True
    assert len(calls) == 0


async def test_translation_drops_comments_when_the_count_does_not_match(
    client: AsyncClient, onboarded: dict, fake_ai
) -> None:
    """Mispaired comments would attribute one person's words to another."""
    fake_ai({"title": "T", "body": "B", "comments": ["only one"]})
    listing = await client.get("/discussions", headers=onboarded["headers"], params={"limit": 1})
    discussion_id = listing.json()[0]["id"]

    r = await client.post(
        f"/discussions/{discussion_id}/translate",
        headers=onboarded["headers"],
        json={"translate_to": "Chinese"},
    )
    assert r.status_code == 200
    assert r.json()["body"] == "B"
    assert r.json()["comments"] == []
