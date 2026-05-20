"""Acceptance tests for the retry_policy feature.

The retry path is exercised by wrapping the implementation's lowest-level write so it
raises TransientStoreError N times before succeeding. The test patches every plausible
write primitive used by a stdlib-only filesystem store; the assertion is that *some*
combination of retry and a final write call delivers the record to the store.

This is implementation-coupled but unavoidable: any retry feature is necessarily about
recovery from a real I/O fault, and the test has to inject one. The test counts retries
indirectly via observed sleeps so a single-attempt design is still caught.
"""
from __future__ import annotations

import pathlib

import pytest


def _patch_writes(monkeypatch, fail_n: int, root_prefix: str):
    """Replace common write primitives so the first `fail_n` writes under `root_prefix`
    raise TransientStoreError; subsequent writes pass through."""
    from src.errors import TransientStoreError

    state = {"failures_left": fail_n}

    def maybe_fail(path_str: str):
        if state["failures_left"] > 0 and path_str.startswith(root_prefix):
            state["failures_left"] -= 1
            raise TransientStoreError("simulated transient failure")

    real_write_bytes = pathlib.Path.write_bytes
    real_write_text = pathlib.Path.write_text
    real_open = open  # noqa: A001

    def flaky_write_bytes(self, data, *a, **kw):
        maybe_fail(str(self))
        return real_write_bytes(self, data, *a, **kw)

    def flaky_write_text(self, data, *a, **kw):
        maybe_fail(str(self))
        return real_write_text(self, data, *a, **kw)

    def flaky_open(file, mode="r", *a, **kw):
        if isinstance(file, (str, pathlib.Path)) and any(c in mode for c in "wax"):
            maybe_fail(str(file))
        return real_open(file, mode, *a, **kw)

    monkeypatch.setattr(pathlib.Path, "write_bytes", flaky_write_bytes)
    monkeypatch.setattr(pathlib.Path, "write_text", flaky_write_text)
    monkeypatch.setattr("builtins.open", flaky_open)
    return state


def test_retry_recovers_from_transient_failure(xml_file, store_root, monkeypatch):
    from src.pipeline import Pipeline, RetryPolicy

    sleeps: list[float] = []
    policy = RetryPolicy(max_attempts=3, base_delay=0.01, sleep=lambda d: sleeps.append(d))
    _patch_writes(monkeypatch, fail_n=2, root_prefix=store_root)

    pipeline = Pipeline(store_root=store_root, retry=policy)
    record_id = pipeline.ingest(str(xml_file))

    assert record_id == "doc-001"
    assert len(sleeps) >= 1, "retry path did not invoke the policy's sleep"


def test_retry_gives_up_after_max_attempts(xml_file, store_root, monkeypatch):
    from src.errors import TransientStoreError
    from src.pipeline import Pipeline, RetryPolicy

    policy = RetryPolicy(max_attempts=2, base_delay=0.01, sleep=lambda d: None)
    _patch_writes(monkeypatch, fail_n=999, root_prefix=store_root)

    pipeline = Pipeline(store_root=store_root, retry=policy)
    with pytest.raises(TransientStoreError):
        pipeline.ingest(str(xml_file))


def test_default_pipeline_does_not_retry(xml_file, store_root, monkeypatch):
    """Regression check: a Pipeline constructed without a RetryPolicy must surface the
    very first transient failure, matching pre-retry behavior."""
    from src.errors import TransientStoreError
    from src.pipeline import Pipeline

    _patch_writes(monkeypatch, fail_n=1, root_prefix=store_root)

    pipeline = Pipeline(store_root=store_root)
    with pytest.raises(TransientStoreError):
        pipeline.ingest(str(xml_file))
