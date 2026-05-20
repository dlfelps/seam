"""Acceptance tests for the metrics feature."""
from __future__ import annotations

import pytest


def test_metrics_counts_ingest(xml_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    pipeline.ingest(str(xml_file))
    snap = pipeline.metrics()
    assert snap["documents_ingested"] >= 1


def test_metrics_counts_queries(xml_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    rid = pipeline.ingest(str(xml_file))
    pipeline.get(rid)
    pipeline.get("missing")
    snap = pipeline.metrics()
    assert snap["queries_served"] >= 2


def test_metrics_counts_parse_errors(malformed_xml_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    with pytest.raises(Exception):
        pipeline.ingest(str(malformed_xml_file))
    snap = pipeline.metrics()
    assert snap["parse_errors"] >= 1


def test_metrics_isolated_per_pipeline(xml_file, store_root, tmp_path):
    """Constructing a fresh Pipeline must reset counters."""
    from src.pipeline import Pipeline

    p1 = Pipeline(store_root=store_root)
    p1.ingest(str(xml_file))
    assert p1.metrics()["documents_ingested"] >= 1

    other_root = tmp_path / "other"
    other_root.mkdir()
    p2 = Pipeline(store_root=str(other_root))
    assert p2.metrics()["documents_ingested"] == 0
