# Seam Benchmark

A reproducible (but **not** auto-executed) experiment that quantifies the trade-off Seam makes:
extra tokens during interface design in exchange for more stable contracts as a project evolves.

This directory holds the prompts, acceptance tests, and harness scripts. Running the benchmark
requires an authenticated Claude Code install — a Pro or Max subscription, an Anthropic API
key, or Bedrock/Vertex credentials all work. CI does not run it.

A full pass is 38 Claude Code invocations (3 features → 6 orderings → 18 feature-step
invocations + 1 base build per condition × 2 conditions). That fits comfortably inside Pro's
5-hour rate window.

## Hypothesis

> Compared to single-shot codegen, Seam spends more tokens up front (Architect + Critic loop)
> but suffers fewer regressions when features are added in arbitrary order, because the
> contracts it commits to are pre-stress-tested against plausible future extensions.

The benchmark measures both sides of that trade — token cost and end-to-end success rate —
across every possible ordering of three extension requests.

## What is held constant

- The base system specification (`spec.md`).
- The three feature prompts (`features/*.md`).
- The acceptance tests (`tests/*`).
- The output directory the generated code must live in (`./src/`, matching Seam's convention).
- The Claude Code CLI version, the default model, and the working directory between runs.

## What varies

- **Condition** — `baseline` (one Claude Code prompt per step) vs `seam` (`/seam-gen` per step).
- **Ordering** — all 6 permutations of the three features.

## Procedure

```
                       ┌─────────────────────────────────────────────────────┐
                       │  Step 0: build base from spec.md                    │
                       │  ─ skip if .cache/base/<mode>.tar.gz exists         │
                       │  ─ otherwise: prompt, run tests/test_base.py,       │
                       │    tar workdir/src → .cache/base/<mode>.tar.gz      │
                       └───────────────────┬─────────────────────────────────┘
                                           │
             for each of the 6 orderings ──┤
                                           ▼
        ┌──────────────────────────────────────────────────────────────────┐
        │  prev = .cache/base/<mode>.tar.gz                                │
        │  for each feature F in the ordering:                             │
        │     step_dir = .cache/<mode>/<NN-perm>/<NN-F>/                   │
        │     if step_dir/status exists:  prev = step_dir/src.tar.gz; skip │
        │     restore prev → workdir/src                                   │
        │     prompt with features/<F>.md (or /seam-gen)                   │
        │     run cumulative pytest (base ∪ features so far)               │
        │     tar workdir/src → step_dir/src.tar.gz                        │
        │     write claude.json, tests.log, status                         │
        │     prev = step_dir/src.tar.gz                                   │
        └──────────────────────────────────────────────────────────────────┘
```

Run once with `./harness/run.sh baseline` and once with `./harness/run.sh seam`. Both are
resumable — see [Caching and resume](#caching-and-resume). When both have completed,
`python harness/score.py .cache/baseline .cache/seam` prints the comparison table.

## Caching and resume

State lives in `benchmarks/.cache/` (gitignored). The layout:

```
.cache/
├── base/
│   ├── baseline.tar.gz       static base src/ for baseline mode
│   ├── baseline.json         raw Claude output for the base build
│   ├── baseline.status       pass | fail (test_base.py against the base build)
│   ├── seam.tar.gz           static base src/ for seam mode
│   ├── seam.json
│   └── seam.status
├── baseline/
│   ├── orderings.txt
│   └── 01-json_format_metrics_retry_policy/
│       ├── 01-json_format/
│       │   ├── claude.json
│       │   ├── status        pass | fail (cumulative pytest)
│       │   ├── status.log    pytest output
│       │   └── src.tar.gz    snapshot of src/ AFTER this step
│       ├── 02-metrics/
│       │   └── ...
│       └── 03-retry_policy/
│           └── ...
└── seam/...
```

Resume semantics: any step whose directory contains a `status` file is treated as complete
and is skipped — the cached `src.tar.gz` is used as the input to the next step. Crashed or
rate-limited steps (no `status` file) are cleaned and retried.

- **To force a step to re-run:** `rm -rf .cache/<mode>/<perm>/<step>/`
- **To force the base to rebuild:** `rm .cache/base/<mode>.tar.gz`
- **To clean everything:** `rm -rf .cache`

The base archive is the "static, saved baseline" — once built, every ordering for that mode
restores from the same tarball. If you want to commit a baseline so collaborators run
against identical generated code, `git add -f .cache/base/baseline.tar.gz .cache/base/seam.tar.gz`.
(They're gitignored by default because they're machine-generated and not always wanted in
version control.)

## Metrics

For each `(mode, ordering, step)` triple the harness records:

- `input_tokens`, `output_tokens`, `cache_read_tokens`, `cache_creation_tokens`
- `cumulative_test_status` — `pass` if every test for every feature added so far still passes
- `wall_time_seconds`

Aggregated by `score.py`:

| Metric | Definition |
| --- | --- |
| `tokens_per_sequence` | sum across the 3 feature steps (excludes base build) |
| `tokens_overhead` | `tokens_per_sequence(seam) − tokens_per_sequence(baseline)`, per ordering |
| `step_success_rate` | fraction of `(ordering, step)` pairs where cumulative tests pass |
| `sequence_success_rate` | fraction of orderings whose 3 steps all pass |
| `regression_rate` | fraction of steps where a previously-passing test fails |

## Diversity rationale for the three features

The three features were chosen so each one stresses a different architectural seam:

| Feature | Axis | What a brittle design will couple to |
| --- | --- | --- |
| `json_format` | data shape | hardcoded XML parser path inside `ingest` |
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
- The base spec and the three feature prompts are written in deliberately neutral prose. A
  prompt that hints at one axis (e.g., "consider future backends") would bias the baseline
  toward the same interfaces Seam discovers. Do not edit them lightly.
- 6 orderings × 2 conditions × 3 steps + 2 base builds = 38 Claude Code invocations per
  full run.

## Files

```
benchmarks/
├── README.md                    # this file
├── .gitignore                   # excludes .cache/ and workdir/
├── spec.md                      # the base requirement (prompt for step 0)
├── features/
│   ├── json_format.md
│   ├── metrics.md
│   └── retry_policy.md
├── tests/
│   ├── conftest.py
│   ├── test_base.py
│   ├── test_json_format.py
│   ├── test_metrics.py
│   └── test_retry_policy.py
└── harness/
    ├── permute.py               # emits the 6 orderings
    ├── run.sh                   # resumable benchmark driver
    ├── measure.py               # extracts token counts from Claude Code JSON output
    └── score.py                 # aggregates .cache/<mode>/ into a summary table
```
