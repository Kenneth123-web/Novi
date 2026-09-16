"""TLS context pinned to certifi.

macOS Python.org builds do not see the system CA store on their own. Pinning
certifi is enough for YouTube and the AI gateway. A leftover HTTP_PROXY is
already disabled via `trust_env=False`; this is the certificate half of that
story.

`SSL_EXTRA_CA` can point at a PEM file when a local SSL-inspection box
(Fortinet, etc.) presents a private root that certifi does not know.
"""

from __future__ import annotations

import os
import ssl

import certifi


def context() -> ssl.SSLContext:
    ctx = ssl.create_default_context(cafile=certifi.where())
    extra_file = os.environ.get("SSL_EXTRA_CA")
    if extra_file and os.path.isfile(extra_file):
        ctx.load_verify_locations(extra_file)
    return ctx
