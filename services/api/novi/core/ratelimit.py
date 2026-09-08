"""Fixed-window rate limiting, per user when known and per IP otherwise."""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass

from fastapi import Request

from novi.config import get_settings
from novi.core.errors import RateLimited
from novi.core.logging import get_logger

logger = get_logger(__name__)


@dataclass(frozen=True)
class Limit:
    times: int
    seconds: int


# AI calls cost real money per request, which is why they get the tight one.
LIMITS = {
    "ai": Limit(20, 60),
    "search": Limit(60, 60),
    "auth": Limit(10, 60),
    "write": Limit(120, 60),
}

_buckets: dict[str, tuple[int, float]] = defaultdict(lambda: (0, 0.0))


def _key(request: Request, name: str) -> str:
    """Authenticated calls key by user. Keying them by IP would make one
    school's NAT share a single AI budget between everyone behind it."""
    user = getattr(request.state, "user", None)
    if user is not None:
        return f"{name}:u:{user.id}"
    forwarded = request.headers.get("x-forwarded-for")
    client = (
        forwarded.split(",")[0].strip()
        if forwarded
        else (request.client.host if request.client else "unknown")
    )
    return f"{name}:ip:{client}"


def rate_limit(name: str):
    limit = LIMITS[name]

    async def _dep(request: Request) -> None:
        if get_settings().env == "test":
            return
        key = _key(request, name)
        now = time.monotonic()
        count, started = _buckets[key]
        if now - started >= limit.seconds:
            _buckets[key] = (1, now)
            return
        if count >= limit.times:
            logger.warning("rate_limited", extra={"limit": name})
            raise RateLimited(
                f"Too many requests. Try again in {int(limit.seconds - (now - started)) + 1}s.",
                details={"limit": limit.times, "window_seconds": limit.seconds},
            )
        _buckets[key] = (count + 1, started)

    return _dep


def reset_limits() -> None:
    """Test hook. Nothing in the request path calls this."""
    _buckets.clear()
