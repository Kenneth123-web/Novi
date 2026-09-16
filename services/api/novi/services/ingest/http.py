"""Shared HTTP client for ingestion.

`trust_env=False` is load-bearing: a leftover HTTP_PROXY from the developer
environment is what made the AI gateway hang, and the same proxy would send
YouTube/Reddit fetches into the same black hole.
"""

from __future__ import annotations

import httpx

from novi.core.tls import context

HEADERS = {
    "User-Agent": "Novi/0.1 (educational ingest; +https://github.com)",
    "Accept": "application/json, application/atom+xml, application/rss+xml, text/xml, */*",
}


def client(*, timeout: float = 20.0) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        timeout=httpx.Timeout(timeout, connect=8.0),
        trust_env=False,
        verify=context(),
        headers=HEADERS,
        follow_redirects=True,
    )
