from __future__ import annotations

from fastapi import APIRouter, Body, Depends, Request, status

from novi.config import get_settings
from novi.core.deps import DB, CurrentUser
from novi.core.ratelimit import client_ip, rate_limit
from novi.schemas.auth import (
    AuthResponse,
    CaptchaConfig,
    DevSkipRequest,
    LoginRequest,
    RefreshRequest,
    RegisterRequest,
    TokenPair,
    UserOut,
)
from novi.schemas.common import Ok
from novi.services import auth_service, turnstile

router = APIRouter(prefix="/auth", tags=["auth"], dependencies=[Depends(rate_limit("auth"))])


# Cloudflare's client-side dummy sitekey. Used only when ENV is not
# production and no real sitekey is configured, so the iOS widget can
# still render in a fresh clone.
_DUMMY_SITEKEY = "1x00000000000000000000AA"
_DEFAULT_WIDGET_URL = "https://novi-console.rememberly-kenneth.workers.dev/turnstile"


def _ua(request: Request) -> str:
    return request.headers.get("user-agent", "")


@router.get("/captcha", response_model=CaptchaConfig)
async def captcha_config() -> CaptchaConfig:
    """Public sitekey + widget host. Register and login still verify server-side."""
    settings = get_settings()
    sitekey = settings.turnstile_sitekey.strip()
    if not sitekey and not settings.is_production:
        sitekey = _DUMMY_SITEKEY
    widget = settings.turnstile_widget_url.strip() or _DEFAULT_WIDGET_URL
    return CaptchaConfig(
        enabled=True,
        sitekey=sitekey,
        widget_url=widget,
    )


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterRequest, request: Request, db: DB) -> AuthResponse:
    await turnstile.verify_turnstile(body.turnstile_token, remote_ip=client_ip(request))
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
    await turnstile.verify_turnstile(body.turnstile_token, remote_ip=client_ip(request))
    user, tokens = await auth_service.login(
        db, email=body.email, password=body.password, user_agent=_ua(request)
    )
    return AuthResponse(user=UserOut.model_validate(user), tokens=tokens)


@router.post("/dev-skip", response_model=AuthResponse)
async def dev_skip(
    request: Request,
    db: DB,
    body: DevSkipRequest = Body(default_factory=DevSkipRequest),
) -> AuthResponse:
    """Issue a real session for the reserved developer account.

    Exists so a local build can reach the product without a password. In
    production the route 404s unless DEV_SKIP_SECRET is set, and then the
    body must carry that secret.
    """
    user, tokens = await auth_service.skip_login(
        db, secret=body.secret, user_agent=_ua(request)
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
