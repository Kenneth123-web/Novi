from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query
from sqlalchemy import text

from novi import __version__
from novi.ai.gateway import gateway
from novi.config import get_settings
from novi.core.deps import DB

router = APIRouter(tags=["health"])


@router.get("/health", summary="Liveness")
async def health() -> dict[str, Any]:
    return {"status": "ok", "version": __version__, "env": get_settings().env}


@router.get("/health/ready", summary="Readiness")
async def ready(
    db: DB,
    # Off by default: probing the AI gateway costs a real request, and a load
    # balancer polling readiness every 10s would spend the budget on health
    # checks.
    check_ai: bool = Query(default=False),
) -> dict[str, Any]:
    checks: dict[str, Any] = {}
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:  # reported in the payload, not raised
        checks["database"] = f"error: {type(exc).__name__}"

    checks["ai"] = await gateway.health() if check_ai else (
        {"status": "configured" if get_settings().ai_configured else "unconfigured"}
    )

    healthy = checks["database"] == "ok"
    return {"status": "ok" if healthy else "degraded", "checks": checks}
