"""Fixed-window rate limiting, per user when known and per IP otherwise."""

from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass

from fastapi import Request

from novi.config import get_settings
from novi.core.deps import CurrentUser
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
    "internal": Limit(30, 60),
}

_buckets: dict[str, tuple[int, float]] = defaultdict(lambda: (0, 0.0))


def client_ip(request: Request) -> str:
    """The connecting address, not a client-supplied X-Forwarded-For.

    Those headers are trivial to spoof unless this process sits behind
    Cloudflare. TRUST_CLOUDFLARE=true is what opts into CF-Connecting-IP.
    """
    if get_settings().trust_cloudflare:
        cf = request.headers.get("cf-connecting-ip")
        if cf:
            return cf.strip()
        forwarded = request.headers.get("x-forwarded-for")
        if forwarded:
            return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _key(request: Request, name: str) -> str:
    """Authenticated calls key by user. Keying them by IP would make one
    school's NAT share a single AI budget between everyone behind it."""
    user = getattr(request.state, "user", None)
    if user is not None:
        return f"{name}:u:{user.id}"
    return f"{name}:ip:{client_ip(request)}"


def _check(request: Request, name: str) -> None:
    if get_settings().env == "test":
        return
    limit = LIMITS[name]
    # Local skip/login retries from a phone and the simulator share one IP.
    # Ten per minute is right for production; here it turns a second tap of
    # "Skip as developer" into a false failure.
    if name == "auth" and get_settings().env == "development":
        limit = Limit(60, 60)
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


def rate_limit(name: str, *, per_user: bool = False):
    """FastAPI `dependencies=` run before path parameters.

    Without `per_user=True` the AI/write limits would fire before
    `current_user` wrote `request.state.user`, so every call would key by IP
    even when a Bearer token was present.
    """
    if name not in LIMITS:
        raise KeyError(name)

    if per_user:

        async def _authed(request: Request, user: CurrentUser) -> None:
            request.state.user = user
            _check(request, name)

        return _authed

    async def _anon(request: Request) -> None:
        _check(request, name)

    return _anon


def reset_limits() -> None:
    """Test hook. Nothing in the request path calls this."""
    _buckets.clear()
