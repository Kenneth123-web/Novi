from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class ErrorBody(BaseModel):
    code: str
    message: str
    details: dict | None = None
    request_id: str | None = None


class ErrorEnvelope(BaseModel):
    """Documented so the OpenAPI schema shows clients the real error shape."""

    error: ErrorBody


class Ok(BaseModel):
    ok: bool = True
