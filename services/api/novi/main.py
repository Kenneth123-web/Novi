"""Application factory."""

from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from novi import __version__
from novi.config import get_settings
from novi.core.errors import install_error_handlers
from novi.core.logging import RequestContextMiddleware, configure_logging, get_logger
from novi.db import dispose_engine
from novi.routers import ask, auth, catalog, feed, health, internal, me, passport
from novi.schemas.common import ErrorEnvelope

logger = get_logger(__name__)

DESCRIPTION = """
Novi — an AI social learning app.

Every failure, at every status code, returns the same shape:

```json
{"error": {"code": "RESOURCE_NOT_FOUND", "message": "...", "request_id": "..."}}
```

Authenticate with `Authorization: Bearer <access_token>`.

The AI gateway key lives on this service and is never sent to a client: the
app calls `POST /v1/ask`, and this calls Gemini.
"""


class RequestBodyLimitMiddleware:
    """Reject oversized HTTP bodies before request parsing or persistence."""

    def __init__(self, app: ASGIApp, max_bytes: int) -> None:
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = dict(scope.get("headers", []))
        try:
            declared = int(headers.get(b"content-length", b"0"))
        except ValueError:
            declared = self.max_bytes + 1
        if declared > self.max_bytes:
            await self._reject(send)
            return

        chunks: list[bytes] = []
        seen = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            chunks.append(chunk)
            seen += len(chunk)
            if seen > self.max_bytes:
                await self._reject(send)
                return
            if not message.get("more_body", False):
                break

        delivered = False

        async def replay_receive() -> Message:
            nonlocal delivered
            if delivered:
                return {"type": "http.disconnect"}
            delivered = True
            return {"type": "http.request", "body": b"".join(chunks), "more_body": False}

        await self.app(scope, replay_receive, send)

    async def _reject(self, send: Send) -> None:
        body = b'{"error":{"code":"PAYLOAD_TOO_LARGE","message":"Request body is too large"}}'
        await send(
            {
                "type": "http.response.start",
                "status": 413,
                "headers": [
                    (b"content-type", b"application/json"),
                    (b"content-length", str(len(body)).encode()),
                ],
            }
        )
        await send({"type": "http.response.body", "body": body})


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    s = get_settings()
    configure_logging(s.log_level, json_output=s.is_production)
    s.check_production()
    logger.info(
        "api_starting",
        extra={"version": __version__, "env": s.env, "ai_configured": s.ai_configured},
    )
    if not s.ai_configured:
        # Loud, because every AI route will answer 503 until this is fixed and
        # that is much easier to diagnose at boot than at first use.
        logger.warning("ai_not_configured", extra={"hint": "set AI_API_KEY in .env"})
    yield
    await dispose_engine()
    logger.info("api_stopped")


def create_app() -> FastAPI:
    s = get_settings()
    # Production does not advertise the schema. /docs is a map of every
    # route, including the ones an attacker would otherwise have to guess.
    docs = None if s.is_production else "/docs"
    openapi = None if s.is_production else "/openapi.json"
    app = FastAPI(
        title="Novi API",
        version=__version__,
        description=DESCRIPTION,
        lifespan=lifespan,
        docs_url=docs,
        redoc_url=None if s.is_production else "/redoc",
        openapi_url=openapi,
        responses={
            401: {"model": ErrorEnvelope, "description": "Not authenticated"},
            404: {"model": ErrorEnvelope, "description": "Not found"},
            422: {"model": ErrorEnvelope, "description": "Validation failed"},
            429: {"model": ErrorEnvelope, "description": "Rate limited"},
            503: {"model": ErrorEnvelope, "description": "AI unavailable"},
        },
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=s.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
        expose_headers=["x-request-id"],
    )
    app.add_middleware(RequestBodyLimitMiddleware, max_bytes=s.max_request_body_bytes)
    # Outermost, so the request id already exists when an error handler builds
    # its response body.
    app.add_middleware(RequestContextMiddleware)

    install_error_handlers(app)

    for router in (
        health.router,
        auth.router,
        me.router,
        catalog.router,
        feed.router,
        ask.router,
        passport.router,
        internal.router,
    ):
        app.include_router(router, prefix="/v1")
    # Also unversioned: a load balancer's health check is configured once and
    # should outlive the API version.
    app.include_router(health.router)

    return app


app = create_app()
