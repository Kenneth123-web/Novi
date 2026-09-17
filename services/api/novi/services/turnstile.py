"""Cloudflare Turnstile verification for register and login.

The iOS app (and the console login form) only ever see the public sitekey.
This module is the only place the API talks to the siteverify Worker; the
Worker holds the secret and calls Cloudflare. Missing or invalid tokens fail
closed — no account is created and no session is issued.
"""

from __future__ import annotations

from typing import Any

import httpx

from novi.config import get_settings
from novi.core.errors import APIError, Forbidden
from novi.core.logging import get_logger
from novi.core.tls import context

logger = get_logger(__name__)

# Cloudflare's documented dummy token. Accepted only when ENV is not
# production AND TURNSTILE_SITEVERIFY_URL is unset, so pytest and a fresh
# local API can run without calling the network. Production never takes
# this branch: check_production refuses to boot without a Worker URL.
CLOUDFLARE_DUMMY_TOKEN = "XXXX.DUMMY.TOKEN"  # noqa: S105

_TIMEOUT = httpx.Timeout(8.0, connect=3.0)


def _siteverify_url(raw: str) -> str:
    url = raw.rstrip("/")
    if url.endswith("/siteverify"):
        return url
    return url


async def verify_turnstile(token: str, *, remote_ip: str | None = None) -> None:
    """Raise if the token is missing or Cloudflare does not accept it."""
    token = (token or "").strip()
    if not token:
        raise APIError(
            "Complete the CAPTCHA and try again",
            code="CAPTCHA_REQUIRED",
            status_code=400,
            details={"field": "turnstile_token"},
        )

    settings = get_settings()
    url = (settings.turnstile_siteverify_url or "").strip()
    if not url:
        if settings.is_production:
            raise APIError(
                "CAPTCHA verification is not configured",
                code="CAPTCHA_UNAVAILABLE",
                status_code=503,
            )
        if token == CLOUDFLARE_DUMMY_TOKEN:
            return
        raise Forbidden(
            "CAPTCHA verification failed",
            code="CAPTCHA_FAILED",
            details={"field": "turnstile_token"},
        )

    payload: dict[str, Any] = {"token": token}
    if remote_ip:
        payload["remoteip"] = remote_ip

    try:
        async with httpx.AsyncClient(
            timeout=_TIMEOUT, trust_env=False, verify=context()
        ) as client:
            response = await client.post(
                _siteverify_url(url),
                json=payload,
                headers={"content-type": "application/json"},
            )
    except httpx.HTTPError as exc:
        logger.warning("turnstile_unreachable", extra={"error": type(exc).__name__})
        raise APIError(
            "CAPTCHA verification is temporarily unavailable",
            code="CAPTCHA_UNAVAILABLE",
            status_code=503,
        ) from None

    try:
        body = response.json()
    except ValueError:
        logger.warning("turnstile_bad_body", extra={"status": response.status_code})
        raise APIError(
            "CAPTCHA verification is temporarily unavailable",
            code="CAPTCHA_UNAVAILABLE",
            status_code=503,
        ) from None

    if not isinstance(body, dict):
        raise APIError(
            "CAPTCHA verification is temporarily unavailable",
            code="CAPTCHA_UNAVAILABLE",
            status_code=503,
        )

    if body.get("success") is True:
        return

    if response.status_code >= 500 and "success" not in body:
        logger.warning("turnstile_upstream_error", extra={"status": response.status_code})
        raise APIError(
            "CAPTCHA verification is temporarily unavailable",
            code="CAPTCHA_UNAVAILABLE",
            status_code=503,
        )

    raise Forbidden(
        "CAPTCHA verification failed",
        code="CAPTCHA_FAILED",
        details={"field": "turnstile_token"},
    )
