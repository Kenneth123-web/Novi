from __future__ import annotations

from fastapi import APIRouter

from novi.core.deps import DB, CurrentUser
from novi.schemas.auth import UserOut
from novi.schemas.profile import (
    CURRICULA,
    GOALS,
    GRADES_BY_STAGE,
    LEARNING_PREFERENCES,
    STAGES,
    MeOut,
    OnboardingRequest,
    ProfileOut,
    ProfileUpdate,
)
from novi.services import passport_service, profile_service

router = APIRouter(tags=["me"])


@router.get("/me", response_model=MeOut)
async def read_me(user: CurrentUser, db: DB) -> MeOut:
    profile = await profile_service.get_or_create(db, user)
    return MeOut(user=UserOut.model_validate(user), profile=ProfileOut.model_validate(profile))


@router.patch("/me", response_model=MeOut)
async def update_me(body: ProfileUpdate, user: CurrentUser, db: DB) -> MeOut:
    profile = await profile_service.update(db, user, body)
    return MeOut(user=UserOut.model_validate(user), profile=ProfileOut.model_validate(profile))


@router.post("/onboarding", response_model=MeOut)
async def onboarding(body: OnboardingRequest, user: CurrentUser, db: DB) -> MeOut:
    profile = await profile_service.apply_onboarding(db, user, body)
    return MeOut(user=UserOut.model_validate(user), profile=ProfileOut.model_validate(profile))


@router.get("/onboarding/options")
async def onboarding_options() -> dict:
    """The allowed values, served rather than hard-coded in the client.

    The client still ships its own labels — it has to, for layout — but the
    slugs come from here, so a value the server would reject cannot appear as
    an option on screen.
    """
    return {
        "stages": STAGES,
        "grades_by_stage": GRADES_BY_STAGE,
        "curricula": CURRICULA,
        "learning_preferences": LEARNING_PREFERENCES,
        "goals": GOALS,
    }


@router.get("/me/history")
async def history(user: CurrentUser, db: DB, days: int = 14) -> list[dict]:
    return await passport_service.history(db, user.id, days=min(max(days, 1), 90))
