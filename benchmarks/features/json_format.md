# Feature: JSON format support

Extend the existing document ingestion pipeline under `./src/` to accept JSON documents in
addition to XML.

## Behavior

- `Pipeline.ingest(path: str) -> str` must accept either an `.xml` or `.json` file and
  dispatch to the right parser based on the file extension.
- JSON shape:
  ```json
  {
    "id": "abc-123",
    "title": "Quarterly report",
    "body": "...",
    "timestamp": "2026-05-19T12:00:00Z"
  }
  ```
- A file with an unsupported extension must raise `ValueError`.
- Existing XML ingestion must continue to work; existing tests must continue to pass.

## Constraints

- Standard library only.
- The public surface of `Pipeline` is unchanged.
- `Record` is unchanged.
