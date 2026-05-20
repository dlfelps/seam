# Feature: Operational metrics

Extend the document ingestion pipeline under `./src/` to record operational counters and
expose them on demand.

## Behavior

- `Pipeline` gains a `metrics() -> dict` method that returns a snapshot with at least
  these integer-valued keys:
  - `"documents_ingested"` — total successful `ingest` calls.
  - `"parse_errors"` — count of `ingest` calls that raised a parsing exception.
  - `"queries_served"` — total successful `get` calls (whether or not the record existed).
- Counters reset only when a new `Pipeline` is constructed.
- Counter updates fire regardless of which file format was ingested or which storage
  backend is active. They must keep working if those features are present and continue to
  work if they are not.

## Constraints

- Standard library only.
- The public surface of `Pipeline` is otherwise unchanged.
- `Record` is unchanged.
