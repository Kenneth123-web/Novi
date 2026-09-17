"""The pool must fail fast. A minute-long connect hang is what made
Skip as developer show "the server took too long to answer" while Postgres
was simply down."""

from novi.db import get_engine


def test_engine_pool_times_out_quickly() -> None:
    pool = get_engine().sync_engine.pool
    timeout = pool.timeout() if callable(getattr(pool, "timeout", None)) else pool._timeout
    assert timeout == 5
