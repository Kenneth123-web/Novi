"""One error shape for every failure.

    {"error": {"code": "...", "message": "...", "details": {...},
               "request_id": "..."}}

The client writes one error path. Unhandled exceptions collapse to
INTERNAL_ERROR and the real cause goes to the log under the same request id —
a stack trace is never part of a response body.
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from novi.core.logging import get_logger, request_id_var

logger = get_logger(__name__)


class APIError(Exception):
    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = "BAD_REQUEST"
    message: str = "Request could not be processed"

    def __init__(
        self,
        message: str | None = None,
        *,
        code: str | None = None,
        status_code: int | None = None,
        details: dict[str, Any] | None = None,
    ) -> None:
        self.message = message or self.message
        self.code = code or self.code
        self.status_code = status_code or self.status_code
        self.details = details or {}
        super().__init__(self.message)


class NotFound(APIError):
    status_code = status.HTTP_404_NOT_FOUND
    code = "RESOURCE_NOT_FOUND"
    message = "Not found"


class Unauthorized(APIError):
    status_code = status.HTTP_401_UNAUTHORIZED
    code = "UNAUTHORIZED"
    message = "Authentication required"


class Forbidden(APIError):
    status_code = status.HTTP_403_FORBIDDEN
    code = "FORBIDDEN"
    message = "You do not have access to this"


class Conflict(APIError):
    status_code = status.HTTP_409_CONFLICT
    code = "CONFLICT"
    message = "Already exists"


class ValidationFailed(APIError):
    status_code = status.HTTP_422_UNPROCESSABLE_CONTENT
    code = "VALIDATION_ERROR"
    message = "Request failed validation"


class RateLimited(APIError):
    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    code = "RATE_LIMITED"
    message = "Too many requests"


class AIUnavailable(APIError):
    """The gateway refused or is out of capacity.

    Deliberately distinct from a 500: the app shows a "the tutor is
    unavailable" state and keeps everything else usable, rather than implying
    the whole product is broken.
    """

    status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    code = "AI_UNAVAILABLE"
    message = "The AI tutor is temporarily unavailable"


def error_response(
    status_code: int, code: str, message: str, details: dict[str, Any] | None = None
) -> JSONResponse:
    payload: dict[str, Any] = {"code": code, "message": message}
    if details:
        payload["details"] = details
    if rid := request_id_var.get():
        payload["request_id"] = rid
    return JSONResponse(status_code=status_code, content={"error": payload})


_HTTP_CODES = {
    400: "BAD_REQUEST",
    401: "UNAUTHORIZED",
    403: "FORBIDDEN",
    404: "RESOURCE_NOT_FOUND",
    405: "METHOD_NOT_ALLOWED",
    409: "CONFLICT",
    422: "VALIDATION_ERROR",
    429: "RATE_LIMITED",
    500: "INTERNAL_ERROR",
    503: "SERVICE_UNAVAILABLE",
}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(APIError)
    async def _api(_: Request, exc: APIError) -> JSONResponse:
        return error_response(exc.status_code, exc.code, exc.message, exc.details)

    @app.exception_handler(StarletteHTTPException)
    async def _http(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        code = _HTTP_CODES.get(exc.status_code, "HTTP_ERROR")
        return error_response(exc.status_code, code, str(exc.detail or code))

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        fields = [
            {
                "field": ".".join(str(p) for p in err["loc"][1:]) or str(err["loc"][0]),
                "reason": err["msg"],
            }
            for err in exc.errors()
        ]
        return error_response(
            status.HTTP_422_UNPROCESSABLE_CONTENT,
            "VALIDATION_ERROR",
            "Request failed validation",
            {"fields": fields},
        )

    @app.exception_handler(Exception)
    async def _unhandled(request: Request, exc: Exception) -> JSONResponse:
        logger.exception(
            "unhandled_exception",
            extra={"path": request.url.path, "method": request.method},
        )
        return error_response(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "INTERNAL_ERROR",
            "Something went wrong on our side",
        )
