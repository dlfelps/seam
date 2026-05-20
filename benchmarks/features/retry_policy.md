# Feature: Retry policy for transient failures

Extend the document ingestion pipeline under `./src/` so transient store-write failures
are retried with exponential backoff before surfacing.

## Behavior

- A `RetryPolicy` object is injectable into `Pipeline`:
  - `RetryPolicy(max_attempts: int = 3, base_delay: float = 0.05, sleep=time.sleep)`
  - The `sleep` parameter exists so tests can pass `lambda _: None` and avoid real waits.
- When the store layer raises a `TransientStoreError` during `ingest`, the pipeline
  retries up to `max_attempts` times with exponentially increasing delays
  (`base_delay`, `2*base_delay`, `4*base_delay`, ...).
- If all attempts fail, the original `TransientStoreError` propagates to the caller.
- A non-transient exception (anything that is not `TransientStoreError`) is **not** retried.
- The retry path must work regardless of which storage backend is active and regardless of
  which file format was ingested.

## Constraints

- Standard library only.
- `Pipeline`'s default behavior (no explicit `RetryPolicy`) must remain compatible with the
  earlier spec — a single attempt, no sleeps, no swallowed exceptions.
- `Record` is unchanged.
- Define `TransientStoreError` somewhere importable from `src` (e.g. `src.errors`).
