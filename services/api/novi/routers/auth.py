from __future__ import annotations

from fastapi import APIRouter, Depends, Request, status

from novi.core.deps import DB, CurrentUser
from novi.core.ratelimit import rate_limit
from novi.schemas.auth import (
    AuthResponse,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
    UserOut,
)
from novi.schemas.common import Ok
from novi.services import auth_service

router = APIRouter(prefix="/auth", tags=["auth"], dependencies=[Depends(rate_limit("auth"))])


def _ua(request: Request) -> str:
    return request.headers.get("user-agent", "")


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, request: Request, db: DB) -> AuthResponse:
    user, tokens = await auth_service.register(
        db,
        email=body.email,
        username=body.username,
        password=body.password,
        display_name=body.display_name,
        user_agent=_ua(request),
    )
    return AuthResponse(user=UserOut.model_validate(user), tokens=tokens)


@router.post("/login", response_model=AuthResponse)
async def login(body: LoginRequest, request: Request, db: DB) -> AuthResponse:
    user, tokens = await auth_service.login(
        db, email=body.email, password=body.password, user_agent=_ua(request)
    )
    return AuthResponse(user=UserOut.model_validate(user), tokens=tokens)


@router.post("/refresh", response_model=TokenPair)
async def refresh(body: RefreshRequest, request: Request, db: DB) -> TokenPair:
    return await auth_service.refresh(
        db, refresh_token=body.refresh_token, user_agent=_ua(request)
    )


@router.post("/logout", response_model=Ok)
async def logout(body: RefreshRequest, db: DB) -> Ok:
    await auth_service.logout(db, refresh_token=body.refresh_token)
    return Ok()


@router.get("/session", response_model=UserOut)
async def whoami(user: CurrentUser) -> UserOut:
    return UserOut.model_validate(user)
