#!/usr/bin/env bash
# Drive one condition of the Seam benchmark end-to-end.
#
# Usage:
#   ./harness/run.sh baseline
#   ./harness/run.sh seam
#
# Run this from the benchmarks/ directory. It assumes:
#   - the `claude` CLI is on PATH and authenticated
#   - `pytest` is installed in the active environment
#   - the Seam plugin is loadable from the repo (e.g., `claude --plugin-dir ..`)
#
# The script is intentionally serial so failures can be inspected. It does NOT
# automatically retry Claude Code on transient errors; re-run the script with the
# same ordering file pointer to resume.

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
WORKDIR="$BENCH_DIR/workdir"
SNAPSHOT="$BENCH_DIR/.snapshot"
TS="$(date +%Y%m%d-%H%M%S)"
RESULTS="$BENCH_DIR/results/$MODE-$TS"

mkdir -p "$RESULTS"
echo "results: $RESULTS"

# ---------- helpers ----------

# Invoke Claude Code with a prompt; in seam mode wrap the prompt in /seam-gen.
# Writes the raw JSON output to $2.
run_claude() {
  local prompt="$1"
  local out="$2"
  if [ "$MODE" = "seam" ]; then
    (cd "$WORKDIR" && claude -p "/seam-gen $prompt" --output-format json) > "$out"
  else
    (cd "$WORKDIR" && claude -p "$prompt" --output-format json) > "$out"
  fi
}

# Run the cumulative pytest suite for the given list of feature names and the base.
# Writes pass/fail to $2.
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

# ---------- step 0: build the base ----------

rm -rf "$WORKDIR" "$SNAPSHOT"
mkdir -p "$WORKDIR"
echo "==> base build ($MODE)"
run_claude "$(cat "$BENCH_DIR/spec.md")" "$RESULTS/base.json"

base_features=()
run_tests base_features "$RESULTS/base.status"
echo "    base tests: $(cat "$RESULTS/base.status")"

cp -r "$WORKDIR/src" "$SNAPSHOT"

# ---------- step 1..N: each ordering ----------

orderings_file="$RESULTS/orderings.txt"
python "$BENCH_DIR/harness/permute.py" > "$orderings_file"
total=$(wc -l < "$orderings_file")
idx=0

while IFS=',' read -ra features; do
  idx=$((idx + 1))
  perm_tag=$(IFS=_; echo "${features[*]}")
  perm_dir="$RESULTS/$(printf '%02d-%s' "$idx" "$perm_tag")"
  mkdir -p "$perm_dir"
  echo "==> [$idx/$total] $perm_tag"

  # restore snapshot
  rm -rf "$WORKDIR/src"
  cp -r "$SNAPSHOT" "$WORKDIR/src"

  added=()
  for f in "${features[@]}"; do
    added+=("$f")
    echo "    + $f"
    run_claude "$(cat "$BENCH_DIR/features/$f.md")" "$perm_dir/$f.json"
    run_tests added "$perm_dir/$f.status"
    echo "      tests: $(cat "$perm_dir/$f.status")"
  done
done < "$orderings_file"

echo "done — see $RESULTS"
