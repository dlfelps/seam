"""Acceptance tests for the s3_backend feature."""
from __future__ import annotations


def test_s3store_construct_put_get(tmp_path):
    from src.s3_store import S3Store  # noqa: F401  (import path may also be src.store.s3_store)

    bucket = S3Store(bucket="benchmark")
    bucket.put("records/doc-001", b"payload")
    assert bucket.get("records/doc-001") == b"payload"


def test_s3store_list_keys():
    from src.s3_store import S3Store

    bucket = S3Store(bucket="benchmark")
    bucket.put("records/a", b"1")
    bucket.put("records/b", b"2")
    assert sorted(bucket.list_keys()) == ["records/a", "records/b"]


def test_pipeline_with_s3_backend(xml_file):
    from src.pipeline import Pipeline
    from src.s3_store import S3Store

    bucket = S3Store(bucket="benchmark")
    pipeline = Pipeline(store=bucket)
    record_id = pipeline.ingest(str(xml_file))
    record = pipeline.get(record_id)

    assert record is not None
    assert record.id == "doc-001"
    assert "doc-001" in pipeline.list_ids()


def test_filesystem_backend_still_works(xml_file, store_root):
    """Regression — the default filesystem path must keep working."""
    from src.pipeline import Pipeline

    pipeline = Pipeline(store_root=store_root)
    record_id = pipeline.ingest(str(xml_file))
    assert pipeline.get(record_id) is not None
