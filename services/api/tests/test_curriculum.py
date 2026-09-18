"""Grade catalog, customization, and the passport course map."""

from __future__ import annotations

import os
import sys

from httpx import AsyncClient
from sqlalchemy import select

from novi.curriculum import (
    COURSES_BY_SLUG,
    GRADE_SPECS,
    SCHOOL_REQUIRED_SUBJECTS,
    SUBJECT_TRACKS,
    courses_for_grade,
    inferred_courses,
    remap_courses,
)
from novi.db import get_sessionmaker
from novi.models import Profile, User

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))


def test_catalog_covers_every_supported_grade_and_subject() -> None:
    if REPO_ROOT not in sys.path:
        sys.path.insert(0, REPO_ROOT)
    from database.seeds.catalog import SUBJECTS

    subject_slugs = {subject["slug"] for subject in SUBJECTS}
    assert set(SUBJECT_TRACKS) == subject_slugs
    assert len(COURSES_BY_SLUG) == len(GRADE_SPECS) * len(SUBJECT_TRACKS)
    assert len(COURSES_BY_SLUG) == len(set(COURSES_BY_SLUG))

    for spec in GRADE_SPECS:
        courses = courses_for_grade(spec.stage, spec.slug)
        assert [course.subject_slug for course in courses] == list(SUBJECT_TRACKS)
        for course in courses:
            assert course.slug == f"{spec.stage}-{spec.slug}-{course.subject_slug}"
            assert course.level == spec.level
            assert len(course.skills) == 3
            if spec.stage in {"middle", "high"}:
                expected = (
                    "required" if course.subject_slug in SCHOOL_REQUIRED_SUBJECTS else "recommended"
                )
            else:
                expected = "recommended"
            assert course.requirement == expected


def test_inferred_and_remapped_courses_preserve_order_and_titles() -> None:
    inferred = inferred_courses(
        "high", "11", ["mathematics", "mathematics", "astrology", "physics"]
    )
    assert [item["course_slug"] for item in inferred] == [
        "high-11-mathematics",
        "high-11-physics",
    ]
    remapped = remap_courses(
        "high",
        "9",
        [{"course_slug": "high-11-mathematics", "name": "AP Calculus BC"}],
        extra_subjects=["physics", "mathematics"],
    )
    assert remapped == [
        {"course_slug": "high-9-mathematics", "name": "AP Calculus BC"},
        {"course_slug": "high-9-physics", "name": ""},
    ]


async def test_curriculum_list_matches_the_in_code_catalog(client: AsyncClient) -> None:
    r = await client.get("/curriculum")
    assert r.status_code == 200, r.text
    body = r.json()
    assert [(row["stage"], row["slug"]) for row in body] == [
        (spec.stage, spec.slug) for spec in GRADE_SPECS
    ]
    assert all(row["age_range"] and row["label"] for row in body)


async def test_grade_curriculum_is_complete_and_rejects_unknown(
    client: AsyncClient, seeded: None
) -> None:
    unknown = await client.get("/curriculum/high/13")
    assert unknown.status_code == 422

    r = await client.get("/curriculum/high/11")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["grade_label"] == "Grade 11"
    assert body["age_range"] == "Ages 16-17"
    assert {course["subject_slug"] for course in body["courses"]} == set(SUBJECT_TRACKS)
    math = next(course for course in body["courses"] if course["subject_slug"] == "mathematics")
    assert math["slug"] == "high-11-mathematics"
    assert math["requirement"] == "required"
    assert math["skills"]

    college = await client.get("/curriculum/college/freshman")
    assert college.status_code == 200
    assert all(course["requirement"] == "recommended" for course in college.json()["courses"])


async def test_onboarding_options_expose_grades_and_focus_goals(client: AsyncClient) -> None:
    r = await client.get("/onboarding/options")
    assert r.status_code == 200
    body = r.json()
    assert body["grades_by_stage"]["high"] == ["9", "10", "11", "12"]
    assert {item["slug"] for item in body["focus_goals"]} >= {
        "build_foundations",
        "exam_readiness",
        "catch_up",
    }
    biology = body["areas_by_subject"]["biology"]
    assert {item["slug"] for item in biology} == {
        "cells",
        "genetics",
        "physiology",
        "ecology",
    }


async def _onboard_courses(
    client: AsyncClient,
    headers: dict[str, str],
    *,
    stage: str = "high",
    grade: str = "11",
    courses: list[dict[str, str]],
    focus: list[str],
    goals: dict[str, str],
    extra: dict | None = None,
) -> dict:
    payload = {
        "stage": stage,
        "grade": grade,
        "curriculum": "AP",
        "current_courses": courses,
        "focus_subject_slugs": focus,
        "focus_goals": goals,
        "learning_preferences": ["short_video"],
        "goals": ["exam_prep"],
    }
    if extra:
        payload.update(extra)
    r = await client.post("/onboarding", headers=headers, json=payload)
    return r


async def test_onboarding_with_courses_is_the_passport_source(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await _onboard_courses(
        client,
        auth["headers"],
        courses=[
            {"course_slug": "high-11-mathematics", "name": "AP Calculus BC"},
            {"course_slug": "high-11-mathematics", "name": ""},
            {"course_slug": "high-11-computer-science", "name": "CS 2"},
        ],
        focus=["mathematics", "physics"],
        goals={"mathematics": "exam_readiness", "physics": "build_foundations"},
    )
    assert r.status_code == 200, r.text
    profile = r.json()["profile"]
    assert profile["current_courses"] == [
        {"course_slug": "high-11-mathematics", "name": "AP Calculus BC"},
        {"course_slug": "high-11-computer-science", "name": "CS 2"},
    ]
    assert profile["subject_order"][:2] == ["mathematics", "computer-science"]
    assert profile["weak_subjects"] == ["mathematics", "physics"]
    assert profile["focus_goals"]["mathematics"] == "exam_readiness"

    passport = await client.get("/passport", headers=auth["headers"])
    assert passport.status_code == 200, passport.text
    body = passport.json()
    assert body["curriculum"]["grade"] == "11"
    assert body["curriculum"]["selection_source"] == "saved"
    assert len(body["course_map"]) == len(SUBJECT_TRACKS)

    by_slug = {course["slug"]: course for course in body["course_map"]}
    math = by_slug["high-11-mathematics"]
    assert math["lane"] == "focus"
    assert math["is_current"] is True
    assert math["is_focus"] is True
    assert math["name"] == "AP Calculus BC"
    assert math["canonical_name"] == "Functions, Trigonometry & Statistics"
    assert math["focus_goal"] == "Prepare for an exam"
    reason = math["recommendation_reason"].lower()
    assert "exam" in reason or "focus" in reason

    cs = by_slug["high-11-computer-science"]
    assert cs["lane"] == "current"
    assert cs["name"] == "CS 2"

    history = by_slug["high-11-history"]
    assert history["lane"] == "required"
    assert history["is_current"] is False

    business = by_slug["high-11-business"]
    assert business["lane"] == "recommended"

    lanes = [course["lane"] for course in body["course_map"]]
    assert lanes == sorted(lanes, key=["focus", "current", "required", "recommended"].index)


async def test_areas_catalog_is_restful_and_rejects_unknown(
    client: AsyncClient,
) -> None:
    listing = await client.get("/areas")
    assert listing.status_code == 200, listing.text
    by_slug = {item["subject_slug"]: item for item in listing.json()}
    assert "biology" in by_slug
    assert {area["slug"] for area in by_slug["biology"]["areas"]} >= {"genetics", "cells"}

    biology = await client.get("/areas/biology")
    assert biology.status_code == 200
    assert biology.json()["subject_name"] == "Biology"
    assert any(area["slug"] == "genetics" for area in biology.json()["areas"])

    missing = await client.get("/areas/astrology")
    assert missing.status_code == 404


async def test_legacy_subjects_still_onboard_and_fill_the_map(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await client.post(
        "/onboarding",
        headers=auth["headers"],
        json={
            "stage": "high",
            "grade": "11",
            "subject_slugs": ["mathematics", "computer-science"],
            "weak_subject_slugs": ["mathematics"],
        },
    )
    assert r.status_code == 200, r.text
    profile = r.json()["profile"]
    assert profile["current_courses"] == [
        {"course_slug": "high-11-mathematics", "name": ""},
        {"course_slug": "high-11-computer-science", "name": ""},
    ]
    passport = (await client.get("/passport", headers=auth["headers"])).json()
    assert passport["curriculum"]["selection_source"] == "saved"
    math = next(c for c in passport["course_map"] if c["slug"] == "high-11-mathematics")
    assert math["is_current"] and math["is_focus"]


async def test_onboarding_rejects_wrong_grade_duplicates_and_bad_goals(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    wrong_grade = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-9-mathematics", "name": ""}],
        focus=["mathematics"],
        goals={"mathematics": "catch_up"},
    )
    assert wrong_grade.status_code == 422
    assert wrong_grade.json()["error"]["details"]["field"] == "current_courses"

    missing_goal = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-mathematics", "name": ""}],
        focus=["mathematics"],
        goals={},
    )
    assert missing_goal.status_code == 422
    assert missing_goal.json()["error"]["details"]["field"] == "focus_goals"

    extra_goal = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-mathematics", "name": ""}],
        focus=["mathematics"],
        goals={"mathematics": "catch_up", "physics": "catch_up"},
    )
    assert extra_goal.status_code == 422


async def test_patching_customization_rewrites_the_passport(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    created = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-mathematics", "name": "AP Calc BC"}],
        focus=["mathematics"],
        goals={"mathematics": "exam_readiness"},
    )
    assert created.status_code == 200, created.text

    patched = await client.patch(
        "/me",
        headers=auth["headers"],
        json={
            "stage": "high",
            "grade": "9",
            "curriculum": None,
            "current_courses": [
                {"course_slug": "high-9-biology", "name": "Honors Bio"},
            ],
            "focus_subject_slugs": ["biology"],
            "focus_goals": {"biology": "catch_up"},
        },
    )
    assert patched.status_code == 200, patched.text
    profile = patched.json()["profile"]
    assert profile["grade"] == "9"
    assert profile["curriculum"] is None
    assert profile["current_courses"] == [
        {"course_slug": "high-9-biology", "name": "Honors Bio"}
    ]
    assert profile["weak_subjects"] == ["biology"]

    passport = (await client.get("/passport", headers=auth["headers"])).json()
    assert passport["curriculum"]["grade"] == "9"
    assert passport["curriculum"]["framework"] is None
    bio = next(c for c in passport["course_map"] if c["slug"] == "high-9-biology")
    assert bio["lane"] == "focus"
    assert bio["name"] == "Honors Bio"
    assert bio["focus_goal"] == "Catch up"
    math = next(c for c in passport["course_map"] if c["slug"] == "high-9-mathematics")
    assert math["is_current"] is False
    assert math["is_focus"] is False


async def test_grade_change_without_new_picks_keeps_local_titles(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    created = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-mathematics", "name": "AP Calc BC"}],
        focus=["mathematics"],
        goals={"mathematics": "get_ahead"},
    )
    assert created.status_code == 200, created.text

    patched = await client.patch(
        "/me",
        headers=auth["headers"],
        json={"stage": "high", "grade": "10"},
    )
    assert patched.status_code == 200, patched.text
    courses = patched.json()["profile"]["current_courses"]
    assert courses == [{"course_slug": "high-10-mathematics", "name": "AP Calc BC"}]
    passport = (await client.get("/passport", headers=auth["headers"])).json()
    math = next(c for c in passport["course_map"] if c["subject_slug"] == "mathematics")
    assert math["slug"] == "high-10-mathematics"
    assert math["name"] == "AP Calc BC"


async def test_passport_without_a_grade_has_an_empty_map(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await client.get("/passport", headers=auth["headers"])
    assert r.status_code == 200
    body = r.json()
    assert body["curriculum"] is None
    assert body["course_map"] == []


async def test_malformed_saved_courses_do_not_break_me(
    client: AsyncClient, auth: dict
) -> None:
    await client.get("/me", headers=auth["headers"])
    async with get_sessionmaker()() as db:
        user = (
            await db.execute(select(User).where(User.email == auth["user"]["email"]))
        ).scalar_one()
        profile = (
            await db.execute(select(Profile).where(Profile.user_id == user.id))
        ).scalar_one()
        profile.current_courses = [{"bad": True}, "nope", {"course_slug": ""}]
        profile.focus_goals = {"ok": 1, "": "catch_up"}  # type: ignore[assignment]
        profile.focus_areas = {"biology": "genetics"}  # type: ignore[assignment]
        await db.commit()

    me = await client.get("/me", headers=auth["headers"])
    assert me.status_code == 200, me.text
    assert me.json()["profile"]["current_courses"] == []
    assert me.json()["profile"]["focus_goals"] == {}
    assert me.json()["profile"]["focus_areas"] == {}


async def test_onboarding_stores_focus_areas_on_the_passport(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    r = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-biology", "name": "Honors Bio"}],
        focus=["biology"],
        goals={"biology": "exam_readiness"},
        extra={"focus_areas": {"biology": ["genetics", "physiology"]}},
    )
    assert r.status_code == 200, r.text
    assert r.json()["profile"]["focus_areas"] == {
        "biology": ["genetics", "physiology"]
    }

    passport = (await client.get("/passport", headers=auth["headers"])).json()
    bio = next(c for c in passport["course_map"] if c["slug"] == "high-11-biology")
    assert [area["slug"] for area in bio["focus_areas"]] == ["genetics", "physiology"]
    assert "Genetics" in bio["recommendation_reason"]
    math = next(c for c in passport["course_map"] if c["slug"] == "high-11-mathematics")
    assert math["focus_areas"] == []


async def test_unknown_focus_areas_are_rejected(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    unknown = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-biology", "name": ""}],
        focus=["biology"],
        goals={"biology": "catch_up"},
        extra={"focus_areas": {"biology": ["astrology"]}},
    )
    assert unknown.status_code == 422
    assert unknown.json()["error"]["details"]["field"] == "focus_areas"


async def test_partial_focus_areas_leave_other_subjects_whole(
    client: AsyncClient, auth: dict, seeded: None
) -> None:
    """A biology pick must not demand math/history chips too — that is what
    greyed out Continue after the learner had already chosen chapters."""
    r = await _onboard_courses(
        client,
        auth["headers"],
        courses=[
            {"course_slug": "high-11-biology", "name": ""},
            {"course_slug": "high-11-mathematics", "name": ""},
            {"course_slug": "high-11-history", "name": ""},
        ],
        focus=["biology"],
        goals={"biology": "catch_up"},
        extra={"focus_areas": {"biology": ["cells", "ecology"]}},
    )
    assert r.status_code == 200, r.text
    assert r.json()["profile"]["focus_areas"] == {"biology": ["cells", "ecology"]}

    empty = await _onboard_courses(
        client,
        auth["headers"],
        courses=[{"course_slug": "high-11-biology", "name": ""}],
        focus=["biology"],
        goals={"biology": "catch_up"},
        extra={"focus_areas": {}},
    )
    assert empty.status_code == 200, empty.text
    assert empty.json()["profile"]["focus_areas"] == {}
