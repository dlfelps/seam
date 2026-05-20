"""Acceptance tests for the base spec (spec.md). These must pass after every step."""
from __future__ import annotations


def test_ingest_xml_returns_id(xml_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    record_id = pipeline.ingest(str(xml_file))
    assert record_id == "doc-001"


def test_get_round_trips_all_fields(xml_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    record_id = pipeline.ingest(str(xml_file))
    record = pipeline.get(record_id)

    assert record is not None
    assert record.id == "doc-001"
    assert record.title == "First post"
    assert record.body == "Hello world."
    assert record.timestamp == "2026-05-19T12:00:00Z"


def test_list_ids_contains_ingested(xml_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    pipeline.ingest(str(xml_file))
    assert "doc-001" in pipeline.list_ids()


def test_get_returns_none_for_unknown(store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    assert pipeline.get("does-not-exist") is None
