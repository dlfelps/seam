#!/usr/bin/env bash
# Drive one condition of the Seam benchmark end-to-end. Resumable on rate-limit.
#
# Usage:
#   ./harness/run.sh baseline
#   ./harness/run.sh seam
#
# Run from any directory; the script resolves benchmarks/ relative to its own location.
# Assumes the `claude` CLI is on PATH and authenticated, and `pytest` is installed in the
# active environment.
#
# State lives in benchmarks/.cache/ (gitignored). Layout:
#   .cache/base/<mode>.tar.gz                     base src/ for this mode (built once)
#   .cache/base/<mode>.json                       raw Claude output for the base build
#   .cache/base/<mode>.status                     pass | fail (base test result)
#   .cache/<mode>/<NN>-<perm>/<NN>-<feature>/
#       claude.json    raw Claude output for this step
#       tests.log      pytest output
#       status         pass | fail
#       src.tar.gz     snapshot of workdir/src AFTER this step
#
# Resume semantics: any step whose directory contains a `status` file is treated as
# complete and is skipped. To force a step to re-run, delete its directory. To force
# the base to rebuild, delete .cache/base/<mode>.tar.gz.

set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  baseline|seam) ;;
  *)
    echo "usage: $0 baseline|seam" >&2
    exit 2
    ;;
esac

BENCH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$BENCH_DIR/.cache"
WORKDIR="$BENCH_DIR/workdir"
BASE_ARCHIVE="$CACHE/base/$MODE.tar.gz"
BASE_JSON="$CACHE/base/$MODE.json"
BASE_STATUS="$CACHE/base/$MODE.status"

mkdir -p "$CACHE/base" "$CACHE/$MODE"

# ---------- helpers ----------

# Invoke Claude Code in $WORKDIR with a prompt; wrap in /seam-gen in seam mode.
run_claude() {
  local prompt="$1" out="$2"
  if [ "$MODE" = "seam" ]; then
    (cd "$WORKDIR" && claude -p "/seam-gen $prompt" --dangerously-skip-permissions --output-format json) > "$out"
  else
    (cd "$WORKDIR" && claude -p "$prompt" --dangerously-skip-permissions --output-format json) > "$out"
  fi
}

# Run cumulative pytest for [base] + [given features]; write pass/fail to $2.
# Test log goes to $2.log.
run_tests() {
  local -n features=$1
  local status_out=$2
  local test_args=("$BENCH_DIR/tests/test_base.py")
  for f in "${features[@]}"; do
    test_args+=("$BENCH_DIR/tests/test_${f}.py")
  done
  if (cd "$WORKDIR" && python -m pytest -q "${test_args[@]}") > "${status_out}.log" 2>&1; then
    echo "pass" > "$status_out"
  else
    echo "fail" > "$status_out"
  fi
}

# Restore a tarball into $WORKDIR/src, replacing whatever is there.
restore_archive() {
  local archive="$1"
  rm -rf "$WORKDIR/src"
  mkdir -p "$WORKDIR"
  tar -xzf "$archive" -C "$WORKDIR"
}

# Snapshot $WORKDIR/src into $1. $2 (optional) is the run's JSON output,
# used only to enrich the diagnostic when src/ is missing.
snapshot_archive() {
  local archive="$1"
  local claude_json="${2:-}"
  if [ ! -d "$WORKDIR/src" ]; then
    {
      echo "error: expected '$WORKDIR/src' to exist, but it does not. Claude did not"
      echo "produce a ./src/ tree."
      echo
      echo "workdir contents:"
      if [ -d "$WORKDIR" ]; then
        ls -A "$WORKDIR" | sed 's/^/    /' || echo "    (empty)"
      else
        echo "    (workdir does not exist)"
      fi
      echo
      echo "The harness already runs claude with --dangerously-skip-permissions, so this"
      echo "is not a permission issue. Likely causes:"
      echo "  - claude produced a textual response instead of using its editing tools."
      echo "  - claude wrote files somewhere other than the workdir (cwd mismatch)."
      echo "  - In seam mode, /seam-gen was not registered as a slash command (plugin"
      echo "    not installed in the environment where claude -p runs)."
      echo
      if [ -n "$claude_json" ] && [ -f "$claude_json" ]; then
        echo "  See $claude_json for the raw run output (look for result/error fields)."
      else
        echo "  No JSON output captured."
      fi
    } >&2
    exit 1
  fi
  tar -czf "$archive" -C "$WORKDIR" src
}

# ---------- step 0: build (or reuse) the base ----------

if [ -f "$BASE_ARCHIVE" ]; then
  echo "==> base build ($MODE) — cached: $BASE_ARCHIVE"
else
  echo "==> base build ($MODE) — building"
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  run_claude "$(cat "$BENCH_DIR/spec.md")" "$BASE_JSON"
  base_features=()
  run_tests base_features "$BASE_STATUS"
  echo "    base tests: $(cat "$BASE_STATUS")"
  snapshot_archive "$BASE_ARCHIVE" "$BASE_JSON"
fi

# ---------- ordering loop ----------

orderings_file="$CACHE/$MODE/orderings.txt"
python "$BENCH_DIR/harness/permute.py" > "$orderings_file"
total=$(wc -l < "$orderings_file")
idx=0

while IFS=',' read -ra features; do
  idx=$((idx + 1))
  perm_tag=$(IFS=_; echo "${features[*]}")
  ord_dir="$CACHE/$MODE/$(printf '%02d-%s' "$idx" "$perm_tag")"
  mkdir -p "$ord_dir"
  echo "==> [$idx/$total] $perm_tag"

  prev_archive="$BASE_ARCHIVE"
  step_idx=0
  added=()

  for f in "${features[@]}"; do
    step_idx=$((step_idx + 1))
    added+=("$f")
    step_dir="$ord_dir/$(printf '%02d-%s' "$step_idx" "$f")"

    if [ -f "$step_dir/status" ] && [ -f "$step_dir/src.tar.gz" ]; then
      echo "    [$step_idx] $f — cached ($(cat "$step_dir/status"))"
      prev_archive="$step_dir/src.tar.gz"
      continue
    fi

    # Incomplete cache from a prior aborted run — clear it.
    rm -rf "$step_dir"
    mkdir -p "$step_dir"

    echo "    [$step_idx] $f — running"
    restore_archive "$prev_archive"
    run_claude "$(cat "$BENCH_DIR/features/$f.md")" "$step_dir/claude.json"
    run_tests added "$step_dir/status"
    snapshot_archive "$step_dir/src.tar.gz" "$step_dir/claude.json"
    echo "      tests: $(cat "$step_dir/status")"
    prev_archive="$step_dir/src.tar.gz"
  done
done < "$orderings_file"

echo "done — see $CACHE/$MODE"
