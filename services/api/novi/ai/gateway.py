"""The only place the product talks to a model.

An OpenAI-compatible gateway in front of Gemini. Two rules the rest of the
codebase depends on:

* **The key never leaves this process.** The iOS app calls `/v1/ask`; this
  calls the gateway. A key in an app bundle is a key anyone can extract from
  the bundle.
* **Everything comes back parsed.** Callers get a validated dict, or an
  `AIUnavailable`. No caller ever sees raw model text, so no caller has to
  reimplement "did it wrap the JSON in a code fence this time".
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass, field
from typing import Any

import httpx

from novi.config import get_settings
from novi.core.errors import AIUnavailable
from novi.core.logging import get_logger

logger = get_logger(__name__)

# Gateways differ in how they signal "the upstream pool has nothing left".
# These are matched on the message because the status code is often a
# indistinguishable 500 — and this failure means "try later", not "you sent a
# bad request", which is a different thing to tell the user.
_CAPACITY_MARKERS = (
    "accounts exhausted",
    "no available channel",
    "insufficient",
    "quota",
    "rate limit",
    "overloaded",
    "unavailable",
)


@dataclass
class AIResult:
    """A parsed model response plus what it cost to get it."""

    data: dict[str, Any]
    model: str
    input_tokens: int = 0
    output_tokens: int = 0
    latency_ms: int = 0
    raw_text: str = ""
    warnings: list[str] = field(default_factory=list)


def _strip_code_fence(text: str) -> str:
    """Models wrap JSON in ```json fences even when told not to.

    Handling it here rather than tightening the prompt is deliberate: the
    prompt is a request, the parser is a guarantee, and one flaky response
    should not surface to the learner as a broken page.
    """
    stripped = text.strip()
    fence = re.match(r"^```(?:json)?\s*(.*?)\s*```$", stripped, re.DOTALL)
    if fence:
        return fence.group(1).strip()
    return stripped


def _extract_json(text: str) -> dict[str, Any] | None:
    cleaned = _strip_code_fence(text)
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        # Last resort: the outermost {...} in the response. Covers a model that
        # prefixed a sentence of preamble before the object.
        start, end = cleaned.find("{"), cleaned.rfind("}")
        if start == -1 or end <= start:
            return None
        try:
            parsed = json.loads(cleaned[start : end + 1])
        except json.JSONDecodeError:
            return None
    return parsed if isinstance(parsed, dict) else None


class AIGateway:
    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client

    @property
    def configured(self) -> bool:
        return get_settings().ai_configured

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        s = get_settings()
        if not s.ai_configured:
            raise AIUnavailable(
                "No AI provider is configured", details={"reason": "missing_api_key"}
            )

        client = self._client or httpx.AsyncClient(timeout=s.ai_timeout_seconds)
        owns_client = self._client is None
        try:
            response = await client.post(
                f"{s.ai_base_url.rstrip('/')}/chat/completions",
                headers={
                    "Authorization": f"Bearer {s.ai_api_key}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
        except httpx.HTTPError as exc:
            logger.warning("ai_transport_error", extra={"error": type(exc).__name__})
            raise AIUnavailable(
                "Could not reach the AI service", details={"reason": "transport"}
            ) from exc
        finally:
            if owns_client:
                await client.aclose()

        try:
            body = response.json()
        except ValueError:
            raise AIUnavailable(
                "The AI service returned an unreadable response",
                details={"reason": "malformed", "status": response.status_code},
            ) from None

        if isinstance(body, dict) and body.get("error"):
            message = str(body["error"].get("message", "")) or "AI request failed"
            lowered = message.lower()
            reason = (
                "capacity"
                if any(marker in lowered for marker in _CAPACITY_MARKERS)
                else "upstream_error"
            )
            logger.warning(
                "ai_upstream_error",
                extra={"reason": reason, "status": response.status_code, "detail": message[:200]},
            )
            # The upstream message is passed through in `details` rather than
            # in `message`: it is useful in a log and to a developer, and it is
            # not something to put in front of a student.
            raise AIUnavailable(
                "The AI tutor is temporarily unavailable"
                if reason == "capacity"
                else "The AI service could not answer that",
                details={"reason": reason, "upstream": message[:200]},
            )

        if response.status_code >= 400:
            raise AIUnavailable(
                "The AI service rejected the request",
                details={"reason": "http_error", "status": response.status_code},
            )
        return body

    async def complete_json(
        self,
        *,
        system: str,
        user: str,
        model: str | None = None,
        max_tokens: int | None = None,
        temperature: float = 0.4,
        required_keys: tuple[str, ...] = (),
    ) -> AIResult:
        """Ask for a JSON object and return it parsed and key-checked."""
        s = get_settings()
        chosen = model or s.ai_model
        started = time.perf_counter()

        body = await self._post(
            {
                "model": chosen,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                "response_format": {"type": "json_object"},
                "temperature": temperature,
                "max_tokens": max_tokens or s.ai_max_output_tokens,
            }
        )
        latency_ms = int((time.perf_counter() - started) * 1000)

        try:
            text = body["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError):
            raise AIUnavailable(
                "The AI service returned an unexpected shape", details={"reason": "malformed"}
            ) from None

        data = _extract_json(text)
        if data is None:
            logger.warning("ai_unparseable_json", extra={"model": chosen, "sample": text[:200]})
            raise AIUnavailable(
                "The AI response could not be read", details={"reason": "unparseable"}
            )

        warnings = [f"missing key: {k}" for k in required_keys if k not in data]
        if warnings:
            # Missing a section degrades the page, it does not break it: the
            # renderer skips absent sections. Failing the whole request here
            # would turn a partial answer into no answer.
            logger.warning("ai_missing_keys", extra={"model": chosen, "missing": warnings})

        usage = body.get("usage") or {}
        return AIResult(
            data=data,
            model=chosen,
            input_tokens=int(usage.get("prompt_tokens") or 0),
            output_tokens=int(usage.get("completion_tokens") or 0),
            latency_ms=latency_ms,
            raw_text=text,
            warnings=warnings,
        )

    async def health(self) -> dict[str, Any]:
        """A single cheap call, used by /health/ready and the admin view."""
        s = get_settings()
        if not s.ai_configured:
            return {"status": "unconfigured", "model": s.ai_model}
        try:
            await self.complete_json(
                system='Reply with JSON only.',
                user='Return {"ok": true}',
                model=s.ai_model_fast,
                max_tokens=32,
                temperature=0,
            )
        except AIUnavailable as exc:
            return {
                "status": "unavailable",
                "model": s.ai_model,
                "reason": exc.details.get("reason"),
                "detail": exc.details.get("upstream"),
            }
        return {"status": "ok", "model": s.ai_model}


gateway = AIGateway()
