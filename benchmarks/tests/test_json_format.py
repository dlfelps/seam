"""Acceptance tests for the json_format feature."""
from __future__ import annotations

import pytest


def test_ingest_json_returns_id(json_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    record_id = pipeline.ingest(str(json_file))
    assert record_id == "doc-002"


def test_get_round_trips_json_record(json_file, store_root):
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    record_id = pipeline.ingest(str(json_file))
    record = pipeline.get(record_id)

    assert record is not None
    assert record.id == "doc-002"
    assert record.title == "Second post"
    assert record.body == "From JSON."
    assert record.timestamp == "2026-05-19T13:00:00Z"


def test_unsupported_extension_raises_value_error(tmp_path, store_root):
    from src.pipeline import Pipeline

    weird = tmp_path / "doc.yaml"
    weird.write_text("id: foo")
    pipeline = Pipeline(store_root=store_root)
    with pytest.raises(ValueError):
        pipeline.ingest(str(weird))


def test_xml_still_works_after_adding_json(xml_file, store_root):
    """Regression check — adding JSON support must not break XML ingestion."""
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    record_id = pipeline.ingest(str(xml_file))
    assert record_id == "doc-001"
