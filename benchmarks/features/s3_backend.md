# Feature: S3-compatible storage backend

Extend the document ingestion pipeline under `./src/` so records can be stored in an
S3-compatible object store in addition to the local filesystem.

## Behavior

- `Pipeline` gains an optional `store` parameter that accepts either:
  - The existing default (filesystem under `store_root`), used when `store` is omitted, OR
  - An `S3Store` object that exposes the same operations against an in-memory fake
    suitable for tests.
- The in-memory `S3Store` must expose:
  - `S3Store(bucket: str)` — construct an empty in-memory bucket.
  - `put(key: str, value: bytes) -> None`
  - `get(key: str) -> bytes | None`
  - `list_keys() -> list[str]`
- The query API (`Pipeline.get`, `Pipeline.list_ids`) returns the same results regardless
  of which backend is active.

## Constraints

- Standard library only. No boto3, no real S3 calls.
- The filesystem backend must continue to work without changes from callers who use the
  default constructor signature `Pipeline(store_root="...")`.
- `Record` is unchanged.
