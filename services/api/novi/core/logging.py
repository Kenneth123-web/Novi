"""Structured logging with a request id on every line."""

from __future__ import annotations

import json
import logging
import sys
import time
import uuid
from contextvars import ContextVar
from typing import Any

from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import Response

request_id_var: ContextVar[str | None] = ContextVar("request_id", default=None)
user_id_var: ContextVar[str | None] = ContextVar("user_id", default=None)

_RESERVED = set(logging.LogRecord("", 0, "", 0, "", (), None).__dict__) | {
    "message",
    "asctime",
    "taskName",
}


class JSONFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created))
            + f".{int(record.msecs):03d}Z",
            "level": record.levelname,
            "logger": record.name,
            "event": record.getMessage(),
        }
        if rid := request_id_var.get():
            payload["request_id"] = rid
        if uid := user_id_var.get():
            payload["user_id"] = uid
        for key, value in record.__dict__.items():
            if key not in _RESERVED:
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str, ensure_ascii=False)


def configure_logging(level: str = "INFO", *, json_output: bool = True) -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        JSONFormatter()
        if json_output
        else logging.Formatter("%(levelname)-7s %(name)s  %(message)s")
    )
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(level.upper())
    # uvicorn's own access log duplicates ours without the request id.
    logging.getLogger("uvicorn.access").handlers = []
    logging.getLogger("uvicorn.access").propagate = False


def get_logger(name: str) -> logging.Logger:
    return logging.getLogger(name)


_access = get_logger("novi.access")

_USAGE_SKIP = (
    "/health",
    "/v1/health",
    "/docs",
    "/openapi.json",
    "/redoc",
)


def _skip_usage(path: str) -> bool:
    if path.startswith("/v1/internal/") or path.startswith("/internal/"):
        return True
    return path in _USAGE_SKIP or path.startswith("/docs")


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next: RequestResponseEndpoint) -> Response:
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex[:16]
        rid_token = request_id_var.set(rid)
        uid_token = user_id_var.set(None)
        started = time.perf_counter()
        status_code = 500
        try:
            response = await call_next(request)
            status_code = response.status_code
            response.headers["x-request-id"] = rid
            return response
        finally:
            _access.info(
                "request",
                extra={
                    "method": request.method,
                    "endpoint": request.url.path,
                    "status": status_code,
                    "latency_ms": round((time.perf_counter() - started) * 1000, 2),
                },
            )
            path = request.url.path
            if request.method != "OPTIONS" and not _skip_usage(path):
                from novi.services.console_client import report_usage

                report_usage(
                    user_id=user_id_var.get(),
                    method=request.method,
                    path=path,
                    status=status_code,
                    latency_ms=round((time.perf_counter() - started) * 1000, 2),
                    request_id=rid,
                )
            request_id_var.reset(rid_token)
            user_id_var.reset(uid_token)
