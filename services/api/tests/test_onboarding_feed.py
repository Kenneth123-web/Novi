"""Onboarding, the feed, and the signals that change it."""

from __future__ import annotations

from httpx import AsyncClient


async def test_subjects_and_concepts_are_served(client: AsyncClient, seeded: None) -> None:
    r = await client.get("/subjects")
    assert r.status_code == 200
    assert {s["slug"] for s in r.json()} >= {"mathematics", "computer-science"}

    r = await client.get("/concepts", params={"subject_slug": "mathematics"})
    assert any(c["slug"] == "derivatives" for c in r.json())


async def test_onboarding_sets_profile_and_orders_interests(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={
            "stage": "high",
            "grade": "11",
            "curriculum": "AP",
            "subject_slugs": ["mathematics", "computer-science", "physics"],
            "weak_subject_slugs": ["mathematics"],
            "learning_preferences": ["short_video"],
            "goals": ["exam_prep"],
        },
    )
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["user"]["is_onboarded"] is True
    profile = body["profile"]
    # Order is priority and it must survive the round trip.
    assert profile["subject_order"] == ["mathematics", "computer-science", "physics"]
    weights = profile["subject_interests"]
    assert weights["mathematics"] > weights["computer-science"] > weights["physics"]
    assert profile["grade"] == "11"
    assert profile["weak_subjects"] == ["mathematics"]


async def test_onboarding_rejects_unknown_values(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    bad_subject = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={"stage": "high", "grade": "11", "subject_slugs": ["astrology"],
              "weak_subject_slugs": ["astrology"]},
    )
    assert bad_subject.status_code == 422
    assert "astrology" in bad_subject.json()["error"]["details"]["unknown"]

    bad_stage = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={"stage": "postgrad", "grade": "11", "subject_slugs": ["mathematics"],
              "weak_subject_slugs": ["mathematics"]},
    )
    assert bad_stage.status_code == 422
    assert bad_stage.json()["error"]["details"]["field"] == "stage"


async def test_onboarding_needs_grade_and_weak_subjects(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    missing_grade = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={
            "stage": "high",
            "subject_slugs": ["mathematics"],
            "weak_subject_slugs": ["mathematics"],
        },
    )
    assert missing_grade.status_code == 422

    missing_weak = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={"stage": "high", "grade": "11", "subject_slugs": ["mathematics"]},
    )
    assert missing_weak.status_code == 422

    weak_not_studied = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={
            "stage": "high",
            "grade": "11",
            "subject_slugs": ["mathematics"],
            "weak_subject_slugs": ["physics"],
        },
    )
    assert weak_not_studied.status_code == 422
    assert weak_not_studied.json()["error"]["details"]["field"] == "weak_subject_slugs"


async def test_onboarding_needs_at_least_one_subject(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await client.post(
        "/onboarding", headers=auth["headers"], json={"stage": "high", "subject_slugs": []}
    )
    assert r.status_code == 422


async def test_feed_is_personalised_to_chosen_subjects(
    client: AsyncClient, onboarded: dict
) -> None:
    r = await client.get("/feed", headers=onboarded["headers"], params={"limit": 20})
    assert r.status_code == 200
    items = r.json()["items"]
    assert items, "a seeded, onboarded user must get a feed"
    # Every card carries the state the UI needs to draw itself.
    assert all("is_saved" in i and "is_liked" in i for i in items)
    assert all(i["reason"] for i in items), "every card must explain itself"


async def test_weak_subject_pulls_that_subject_forward(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={
            "stage": "high",
            "grade": "11",
            "subject_slugs": ["mathematics", "history"],
            "weak_subject_slugs": ["mathematics"],
            "learning_preferences": [],
            "goals": [],
        },
    )
    assert r.status_code == 200, r.text
    feed = await client.get("/feed", headers=auth["headers"], params={"limit": 12})
    items = feed.json()["items"]
    assert items
    math_slugs = {
        "limits", "derivatives", "chain-rule", "integrals", "functions",
        "linear-equations", "quadratic-equations",
    }
    math_count = sum(
        1
        for i in items
        if any(c["slug"] in math_slugs for c in i["content"]["concepts"])
    )
    assert math_count >= 3, "stuck-on-math should surface math tutorials"
    assert any("hard one" in i["reason"] or "follow" in i["reason"].lower() for i in items)


async def test_two_profiles_get_different_feeds(
    client: AsyncClient, seeded: None, registration: dict
) -> None:
    """The whole point of the recommender, as a test."""

    async def make(subjects: list[str], email_suffix: str) -> list[str]:
        reg = dict(
            registration,
            email=f"{email_suffix}@example.com",
            username=f"u{email_suffix}",
        )
        r = await client.post("/auth/register", json=reg)
        headers = {"Authorization": f"Bearer {r.json()['tokens']['access_token']}"}
        await client.post(
            "/onboarding",
            headers=headers,
            json={"stage": "high", "grade": "11", "subject_slugs": subjects,
                  "weak_subject_slugs": subjects[:1]},
        )
        feed = await client.get("/feed", headers=headers, params={"limit": 20})
        return [i["content"]["id"] for i in feed.json()["items"]]

    mathematician = await make(["mathematics"], "mathy")
    historian = await make(["history"], "histy")

    assert mathematician and historian
    assert set(mathematician).isdisjoint(set(historian))


async def test_feed_excludes_content_already_seen(
    client: AsyncClient, onboarded: dict
) -> None:
    first = await client.get("/feed", headers=onboarded["headers"], params={"limit": 5})
    seen = [i["content"]["id"] for i in first.json()["items"]]
    assert seen

    for content_id in seen:
        r = await client.post(
            "/interactions",
            headers=onboarded["headers"],
            json={"kind": "VIEW", "content_id": content_id, "dwell_seconds": 30},
        )
        assert r.status_code == 200

    second = await client.get("/feed", headers=onboarded["headers"], params={"limit": 20})
    assert set(seen).isdisjoint({i["content"]["id"] for i in second.json()["items"]})


async def test_viewing_content_raises_subject_interest(
    client: AsyncClient, onboarded: dict
) -> None:
    before = (await client.get("/me", headers=onboarded["headers"])).json()["profile"]
    feed = await client.get("/feed", headers=onboarded["headers"], params={"limit": 3})
    item = feed.json()["items"][0]

    await client.post(
        "/interactions",
        headers=onboarded["headers"],
        json={"kind": "LIKE", "content_id": item["content"]["id"]},
    )

    after = (await client.get("/me", headers=onboarded["headers"])).json()["profile"]
    assert after["subject_interests"] != before["subject_interests"]


async def test_interactions_reject_unknown_kinds(client: AsyncClient, auth: dict) -> None:
    r = await client.post(
        "/interactions", headers=auth["headers"], json={"kind": "TELEPORT"}
    )
    assert r.status_code == 422
    assert r.json()["error"]["details"]["field"] == "kind"


async def test_save_is_idempotent_and_reversible(
    client: AsyncClient, onboarded: dict
) -> None:
    feed = await client.get("/feed", headers=onboarded["headers"], params={"limit": 1})
    content_id = feed.json()["items"][0]["content"]["id"]
    h = onboarded["headers"]

    assert (await client.post(f"/content/{content_id}/save", headers=h, json={})).status_code == 200
    assert (await client.post(f"/content/{content_id}/save", headers=h, json={})).status_code == 200

    saved = await client.get("/saved", headers=h)
    assert [c["id"] for c in saved.json()] == [content_id]

    assert (await client.delete(f"/content/{content_id}/save", headers=h)).status_code == 200
    assert (await client.get("/saved", headers=h)).json() == []


async def test_content_detail_carries_concepts_and_related(
    client: AsyncClient, onboarded: dict
) -> None:
    feed = await client.get("/feed", headers=onboarded["headers"], params={"limit": 1})
    content_id = feed.json()["items"][0]["content"]["id"]

    r = await client.get(f"/content/{content_id}", headers=onboarded["headers"])
    assert r.status_code == 200
    body = r.json()
    assert body["concepts"], "content must be linked to at least one concept"
    assert body["related"], "the detail page needs somewhere to go next"
    # Placeholder rows must be identifiable by the client.
    assert body["content"]["is_sample"] is True


async def test_search_finds_a_concept_and_content(
    client: AsyncClient, onboarded: dict
) -> None:
    r = await client.get("/search", headers=onboarded["headers"], params={"q": "Derivatives"})
    assert r.status_code == 200
    body = r.json()
    assert body["concept"] is not None
    assert body["concept"]["name"] == "Derivatives"
    assert body["content"], "search must return content, not only the concept"


async def test_search_handles_a_multiword_query(client: AsyncClient, onboarded: dict) -> None:
    """plainto_tsquery would AND every word and return nothing here."""
    r = await client.get(
        "/search", headers=onboarded["headers"], params={"q": "how do derivatives work"}
    )
    assert r.status_code == 200
    assert r.json()["content"]


async def test_concept_graph_offers_somewhere_to_go_next(
    client: AsyncClient, onboarded: dict
) -> None:
    concepts = await client.get("/concepts", params={"subject_slug": "mathematics"})
    derivatives = next(c for c in concepts.json() if c["slug"] == "derivatives")

    r = await client.get(f"/concepts/{derivatives['id']}", headers=onboarded["headers"])
    assert r.status_code == 200
    assert r.json()["next"], "the rabbit hole must not dead-end"
    assert "chain-rule" in {c["slug"] for c in r.json()["next"]}
