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
from novi.core.tls import context

logger = get_logger(__name__)

# Gateways differ in how they signal "the upstream pool has nothing left".
# These are matched on the message because the status code is often a
# indistinguishable 500 — and this failure means "try later", not "you sent a
# bad request", which is a different thing to tell the user.
ANTHROPIC_VERSION = "2023-06-01"


class ModelUnavailable(Exception):
    """This model did not work. Try the next one in the chain.

    Distinct from AIUnavailable on purpose: it is not a failure to report to
    the learner, it is an instruction to move on.

    `permanent` separates the two ways a model can fail us. `model_not_found`
    is a fact about the account and worth remembering — retrying it on every
    request wastes a round trip forever. "Upstream request failed" might be
    this minute only, so the model is skipped for this request and tried again
    on the next. Caching that one would blacklist a working model over a blip.
    """

    def __init__(self, model: str, message: str, *, permanent: bool) -> None:
        self.model = model
        self.permanent = permanent
        super().__init__(message)


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
        # Models the gateway has told us it cannot serve. Remembered for the
        # process so a five-model fallback chain costs one wasted call, not one
        # per request — `model_not_found` is a fact about the account, not a
        # transient.
        self._unavailable: set[str] = set()

    @property
    def configured(self) -> bool:
        return get_settings().ai_configured

    def candidates(self, preferred: str | None = None) -> list[str]:
        """The model to try, then what to fall back to.

        Order is preserved and duplicates dropped, so a preferred model that is
        also in the fallback list is tried once, first.
        """
        s = get_settings()
        chain = [preferred or s.ai_model, *s.ai_model_fallbacks]
        seen: set[str] = set()
        out: list[str] = []
        for model in chain:
            if model and model not in seen:
                seen.add(model)
                out.append(model)
        return out

    # ── Transport ────────────────────────────────────────────────────────────

    def _endpoint(self) -> str:
        s = get_settings()
        base = s.ai_base_url.rstrip("/")
        return f"{base}/messages" if s.ai_protocol == "anthropic" else f"{base}/chat/completions"

    def _headers(self) -> dict[str, str]:
        s = get_settings()
        if s.ai_protocol == "anthropic":
            return {
                "x-api-key": s.ai_api_key or "",
                "anthropic-version": ANTHROPIC_VERSION,
                "content-type": "application/json",
            }
        return {
            "Authorization": f"Bearer {s.ai_api_key}",
            "Content-Type": "application/json",
        }

    def _build_payload(
        self, *, model: str, system: str, user: str, max_tokens: int, temperature: float
    ) -> dict[str, Any]:
        s = get_settings()
        if s.ai_protocol == "anthropic":
            # `system` is a top-level field here, not a message with a role.
            # Passing it as a message is accepted and then ignored, which is
            # the worst of both: no error, and the model never sees the rules.
            return {
                "model": model,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "system": system,
                "messages": [{"role": "user", "content": user}],
            }
        return {
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "response_format": {"type": "json_object"},
            "temperature": temperature,
            "max_tokens": max_tokens,
        }

    def _extract_text(self, body: dict[str, Any]) -> str | None:
        """The reply text, from either protocol's response shape."""
        if get_settings().ai_protocol == "anthropic":
            blocks = body.get("content")
            if not isinstance(blocks, list):
                return None
            parts = [
                b.get("text", "")
                for b in blocks
                if isinstance(b, dict) and b.get("type") == "text"
            ]
            return "".join(parts) if parts else None
        try:
            return body["choices"][0]["message"]["content"] or ""
        except (KeyError, IndexError, TypeError):
            return None

    @staticmethod
    def _usage(body: dict[str, Any]) -> tuple[int, int]:
        usage = body.get("usage") or {}
        return (
            int(usage.get("input_tokens") or usage.get("prompt_tokens") or 0),
            int(usage.get("output_tokens") or usage.get("completion_tokens") or 0),
        )

    async def _post(self, payload: dict[str, Any]) -> dict[str, Any]:
        s = get_settings()
        if not s.ai_configured:
            raise AIUnavailable(
                "No AI provider is configured", details={"reason": "missing_api_key"}
            )

        client = self._client or httpx.AsyncClient(
            timeout=httpx.Timeout(s.ai_timeout_seconds, connect=10.0),
            trust_env=False,
            verify=context(),
        )
        owns_client = self._client is None
        try:
            response = await client.post(
                self._endpoint(), headers=self._headers(), json=payload
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
            error = body["error"]
            message = str(error.get("message", "")) or "AI request failed"
            kind = str(error.get("type", ""))
            lowered = message.lower()

            # A model the account cannot serve is not a capacity problem — it
            # is a signal to try the next candidate.
            if kind == "model_not_found" or "not supported by any configured" in lowered:
                raise ModelUnavailable(payload.get("model", ""), message, permanent=True)

            # The gateway lists nine Grok models and can actually serve two.
            # The other seven answer "Upstream request failed", which is this
            # gateway's way of saying the model is not really wired up. Treat
            # it as a reason to move down the chain, but do not remember it:
            # the same string is what a genuinely transient blip returns.
            if kind == "upstream_error" or "upstream request failed" in lowered:
                raise ModelUnavailable(payload.get("model", ""), message, permanent=False)

            reason = (
                "capacity"
                if any(marker in lowered for marker in _CAPACITY_MARKERS)
                else "upstream_error"
            )
            logger.warning(
                "ai_upstream_error",
                extra={"reason": reason, "status": response.status_code, "detail": message[:200]},
            )
            raise AIUnavailable(
                "The AI tutor is temporarily unavailable"
                if reason == "capacity"
                else "The AI service could not answer that",
                details={"reason": reason},
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
        """Ask for a JSON object and return it parsed and key-checked.

        Walks the model chain: the preferred model first, then the configured
        fallbacks, skipping any the gateway has already said it cannot serve.
        That is what lets `AI_MODEL` name the model we actually want — Haiku —
        without the product breaking on a gateway that does not carry it yet.
        """
        s = get_settings()
        started = time.perf_counter()

        chain = [m for m in self.candidates(model) if m not in self._unavailable]
        if not chain:
            # Everything we know about has been refused. Try the preferred one
            # anyway: the account's roster can change under us.
            self._unavailable.clear()
            chain = self.candidates(model)

        body: dict[str, Any] | None = None
        chosen = chain[0]
        last: ModelUnavailable | None = None

        for candidate in chain:
            payload = self._build_payload(
                model=candidate,
                system=system,
                user=user,
                max_tokens=max_tokens or s.ai_max_output_tokens,
                temperature=temperature,
            )
            try:
                body = await self._post(payload)
                chosen = candidate
                break
            except ModelUnavailable as exc:
                logger.warning(
                    "ai_model_unavailable",
                    extra={"model": candidate, "permanent": exc.permanent},
                )
                if exc.permanent:
                    self._unavailable.add(candidate)
                last = exc
                continue

        if body is None:
            raise AIUnavailable(
                "No configured AI model is available",
                details={
                    "reason": "no_model",
                    "tried": chain,
                    "upstream": str(last) if last else "",
                },
            )

        latency_ms = int((time.perf_counter() - started) * 1000)

        text = self._extract_text(body)
        if text is None:
            raise AIUnavailable(
                "The AI service returned an unexpected shape", details={"reason": "malformed"}
            )

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

        input_tokens, output_tokens = self._usage(body)
        result = AIResult(
            data=data,
            model=chosen,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=latency_ms,
            raw_text=text,
            warnings=warnings,
        )
        from novi.core.logging import user_id_var
        from novi.services.console_client import report_ai_usage

        report_ai_usage(
            user_id=user_id_var.get(),
            model=chosen,
            input_tokens=input_tokens,
            output_tokens=output_tokens,
            latency_ms=latency_ms,
        )
        return result

    async def health(self) -> dict[str, Any]:
        """A cheap reachability probe, used by /health/ready and the admin view.

        Hits GET /models rather than burning a generation: a load balancer that
        polls this must not spend the tutor budget, and a 90s complete_json
        made the ready check look like an outage when the gateway was merely slow.
        """
        s = get_settings()
        if not s.ai_configured:
            return {"status": "unconfigured", "model": s.ai_model}
        url = f"{s.ai_base_url.rstrip('/')}/models"
        try:
            async with httpx.AsyncClient(
                timeout=httpx.Timeout(8.0, connect=5.0),
                trust_env=False,
                verify=context(),
            ) as client:
                response = await client.get(url, headers=self._headers())
        except httpx.HTTPError as exc:
            return {
                "status": "unavailable",
                "model": s.ai_model,
                "reason": "transport",
                "detail": type(exc).__name__,
            }
        if response.status_code >= 400:
            return {
                "status": "unavailable",
                "model": s.ai_model,
                "reason": "http_error",
                "detail": f"HTTP {response.status_code}",
            }
        return {"status": "ok", "model": s.ai_model}


gateway = AIGateway()
