"""Emit every unique ordering of the four feature names, one per line, as CSV.

Usage:
    python harness/permute.py            # print all 24 orderings
    python harness/permute.py --count    # print the number of orderings only
"""
from __future__ import annotations

import sys
from itertools import permutations

FEATURES = ("json_format", "s3_backend", "metrics", "retry_policy")


def main() -> int:
    if "--count" in sys.argv:
        print(sum(1 for _ in permutations(FEATURES)))
        return 0
    for perm in permutations(FEATURES):
        print(",".join(perm))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
