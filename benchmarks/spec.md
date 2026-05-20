# Base system: Document Ingestion Pipeline

Build a small document ingestion library in Python 3.10+. All code must live under `./src/`.
The library has no UI, no CLI, no network server — it is imported and called.

## Behavior

- Accept XML documents from a caller-supplied filesystem path.
- Parse each document into a normalized `Record` with fields:
  - `id: str`
  - `title: str`
  - `body: str`
  - `timestamp: str` (ISO 8601)
- Persist each record on the local filesystem under a caller-supplied root directory,
  one file per record.
- Expose a `Pipeline` class as the single public entrypoint with this surface:
  - `Pipeline(store_root: str)` — construct.
  - `ingest(path: str) -> str` — read, parse, persist; return the record id.
  - `get(record_id: str) -> Record | None` — fetch a stored record by id.
  - `list_ids() -> list[str]` — return all stored record ids.

## XML shape

```xml
<document>
  <id>abc-123</id>
  <title>Quarterly report</title>
  <body>...</body>
  <timestamp>2026-05-19T12:00:00Z</timestamp>
</document>
```

## Constraints

- Python 3.10+ only. No new third-party dependencies; use the standard library.
- Importable as `from src.pipeline import Pipeline, Record`.
- Records must round-trip: a value written by `ingest` must be returned by `get` with all
  four fields intact.
- `list_ids` returns ids in any order; tests sort before asserting.

The pipeline will be extended in later steps. Do not implement extensions speculatively —
ship only what this spec asks for.
