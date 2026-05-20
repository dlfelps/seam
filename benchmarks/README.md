# Seam Benchmark

A reproducible (but **not** auto-executed) experiment that quantifies the trade-off Seam makes:
extra tokens during interface design in exchange for more stable contracts as a project evolves.

This directory holds the prompts, acceptance tests, and harness scripts. Running the benchmark
requires a Claude Code account with billing enabled; CI does not run it.

## Hypothesis

> Compared to single-shot codegen, Seam spends more tokens up front (Architect + Critic loop)
> but suffers fewer regressions when features are added in arbitrary order, because the
> contracts it commits to are pre-stress-tested against plausible future extensions.

The benchmark measures both sides of that trade — token cost and end-to-end success rate —
across every possible ordering of four extension requests.

## What is held constant

- The base system specification (`spec.md`).
- The four feature prompts (`features/*.md`).
- The acceptance tests (`tests/*`).
- The output directory the generated code must live in (`./src/`, matching Seam's convention).
- The Claude Code CLI version, the default model, and the working directory between runs.

## What varies

- **Condition** — `baseline` (one Claude Code prompt per step) vs `seam` (`/seam-gen` per step).
- **Ordering** — all 24 permutations of the four features.

## Procedure

```
                                 ┌───────────────────────────────────┐
                                 │  Step 0: build base from spec.md  │
                                 │  ─ measure tokens                 │
                                 │  ─ run tests/test_base.py         │
                                 │  ─ snapshot src/  →  .snapshot/   │
                                 └───────────────┬───────────────────┘
                                                 │
                  for each of the 24 orderings ──┤
                                                 ▼
                ┌──────────────────────────────────────────────────────────┐
                │  restore snapshot                                        │
                │  for each feature F in the ordering:                     │
                │     ─ prompt model with features/<F>.md                  │
                │     ─ measure tokens                                     │
                │     ─ run cumulative pytest (base ∪ features so far)     │
                │     ─ record pass/fail and tokens for this step          │
                └──────────────────────────────────────────────────────────┘
```

Run once with `MODE=baseline` and once with `MODE=seam`. The harness writes one JSON record
per step under `results/<mode>-<timestamp>/` and `score.py` aggregates them.

## Metrics

For each `(mode, ordering, step)` triple the harness records:

- `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`
- `cumulative_test_status` — `pass` if every test for every feature added so far still passes
- `wall_time_seconds`

Aggregated by `score.py`:

| Metric | Definition |
| --- | --- |
| `tokens_per_sequence` | sum across the 4 feature steps (excludes base build) |
| `tokens_overhead` | `tokens_per_sequence(seam) − tokens_per_sequence(baseline)`, per ordering |
| `step_success_rate` | fraction of `(ordering, step)` pairs where cumulative tests pass |
| `sequence_success_rate` | fraction of orderings whose 4 steps all pass |
| `regression_rate` | fraction of steps where a previously-passing test fails |

## Diversity rationale for the four features

The four features were chosen so each one stresses a different architectural seam:

| Feature | Axis | What a brittle design will couple to |
| --- | --- | --- |
| `json_format` | data shape | hardcoded XML parser path inside `ingest` |
| `s3_backend` | storage | hardcoded `open(path, "w")` instead of a Store handle |
| `metrics` | cross-cutting concern | counters scattered inline instead of an observer |
| `retry_policy` | behavior | try/except blocks inlined into each call site |

A pipeline that only abstracts *one* of these axes will succeed in some orderings and fail in
others — exactly the asymmetry the benchmark is designed to surface.

## Limitations

- `/seam-gen` as written wipes `./.seam-work/` and writes `./src/` from scratch on each
  invocation. The harness compensates by restoring the snapshot and passing the prior
  source tree as context inside the feature prompt (`features/<name>.md` references
  `./src/`). The Architect must therefore reason about extending an existing tree, not
  greenfield. This is the realistic scenario, but it is a known stress on the agent.
- Token counts depend on Claude Code's prompt-caching behavior, which varies between runs.
- The base spec and the four feature prompts are written in deliberately neutral prose. A
  prompt that hints at one axis (e.g., "consider future backends") would bias the baseline
  toward the same interfaces Seam discovers. Do not edit them lightly.
- 24 orderings × 2 conditions × 4 steps + 2 base builds = 194 Claude Code invocations per
  full run. Expect non-trivial cost.

## Files

```
benchmarks/
├── README.md                    # this file
├── spec.md                      # the base requirement (prompt for step 0)
├── features/
│   ├── json_format.md
│   ├── s3_backend.md
│   ├── metrics.md
│   └── retry_policy.md
├── tests/
│   ├── conftest.py
│   ├── test_base.py
│   ├── test_json_format.py
│   ├── test_s3_backend.py
│   ├── test_metrics.py
│   └── test_retry_policy.py
└── harness/
    ├── permute.py               # emits the 24 orderings
    ├── run.sh                   # full benchmark driver
    ├── measure.py               # extracts token counts from Claude Code JSON output
    └── score.py                 # aggregates results into a summary table
```
