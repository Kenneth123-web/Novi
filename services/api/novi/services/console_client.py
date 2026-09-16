"""Talk to the Cloudflare console Worker.

The console is the ledger for accounts and API usage. This module is the only
place the origin writes to it. Two rules:

* A missing CONSOLE_BASE_URL is a no-op, not an error. Tests and a fresh
  clone must not depend on Cloudflare being up.
* A console outage must not take the product down. Account ingest is awaited
  with a short timeout and swallowed; per-request usage is fire-and-forget.
"""

from __future__ import annotations

import asyncio
from typing import Any

import httpx

from novi.config import get_settings
from novi.core.logging import get_logger
from novi.models import User

logger = get_logger(__name__)

_TIMEOUT = httpx.Timeout(2.5, connect=1.0)
_tasks: set[asyncio.Task[None]] = set()


def _enabled() -> tuple[str, str] | None:
    s = get_settings()
    base = (s.console_base_url or "").rstrip("/")
    if not base:
        return None
    return base, s.console_origin_secret


async def _post(path: str, payload: dict[str, Any]) -> None:
    cfg = _enabled()
    if cfg is None:
        return
    base, secret = cfg
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            response = await client.post(
                f"{base}{path}",
                json=payload,
                headers={
                    "content-type": "application/json",
                    "x-novi-origin-secret": secret,
                },
            )
            if response.status_code >= 400:
                logger.warning(
                    "console_ingest_rejected",
                    extra={"path": path, "status": response.status_code},
                )
    except Exception as exc:
        logger.warning("console_ingest_failed", extra={"path": path, "error": type(exc).__name__})


async def _get_json(path: str) -> dict[str, Any] | None:
    cfg = _enabled()
    if cfg is None:
        return None
    base, secret = cfg
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            response = await client.get(
                f"{base}{path}",
                headers={"x-novi-origin-secret": secret},
            )
    except Exception as exc:
        logger.warning("console_read_failed", extra={"path": path, "error": type(exc).__name__})
        return None
    if response.status_code != 200:
        return None
    try:
        body = response.json()
    except ValueError:
        return None
    return body if isinstance(body, dict) else None


def spawn(coro: Any) -> None:
    """Run a coroutine after the response, if a loop is running."""
    try:
        loop = asyncio.get_running_loop()
    except RuntimeError:
        return
    task = loop.create_task(coro)
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)


async def report_account(
    user: User,
    *,
    event: str,
    source: str,
    user_agent: str = "",
) -> None:
    await _post(
        "/api/ingest/account",
        {
            "id": str(user.id),
            "email": user.email,
            "username": user.username,
            "display_name": user.display_name,
            "is_admin": bool(user.is_admin),
            "is_active": bool(user.is_active),
            "event": event,
            "source": source,
            "user_agent": user_agent[:255],
            "created_at": user.created_at.isoformat() if user.created_at else None,
        },
    )


async def is_blocked(user_id: str) -> bool:
    """True only when the console says this account is inactive.

    Fail open: a console timeout must not lock every learner out.
    """
    body = await _get_json(f"/api/ingest/status/{user_id}")
    if body is None:
        return False
    return body.get("is_active") is False


def report_usage(
    *,
    user_id: str | None,
    method: str,
    path: str,
    status: int,
    latency_ms: float,
    request_id: str | None,
) -> None:
    spawn(
        _post(
            "/api/ingest/usage",
            {
                "user_id": user_id,
                "method": method,
                "path": path[:200],
                "status": status,
                "latency_ms": latency_ms,
                "request_id": request_id,
                "kind": "http",
            },
        )
    )


def report_ai_usage(
    *,
    user_id: str | None,
    model: str,
    input_tokens: int,
    output_tokens: int,
    latency_ms: int,
    path: str = "/v1/ask",
) -> None:
    spawn(
        _post(
            "/api/ingest/usage",
            {
                "user_id": user_id,
                "method": "POST",
                "path": path[:200],
                "status": 200,
                "latency_ms": latency_ms,
                "kind": "ai",
                "model": model,
                "input_tokens": input_tokens,
                "output_tokens": output_tokens,
            },
        )
    )
