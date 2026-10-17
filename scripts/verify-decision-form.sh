#!/usr/bin/env bash
set -euo pipefail
DEFAULT_SOURCE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE=$(cd -- "${1:-$DEFAULT_SOURCE}" && pwd)
ROUND=$(dirname "$SOURCE")
export WORKER_ROOT="${WORKER_ROOT:-$ROUND/worker}"
ENVIRONMENT="${MOON_ENVIRONMENT:-/workspace/scratch/665adc5202cf/.moonsuite-background/build-readiness-20261011T131950/environment.sh}"
source "$ENVIRONMENT"
TARGET="${DECISION_TARGET_DIR:-$ROUND/build}"
[[ "$TARGET" = /* && "$TARGET" != "$SOURCE"/* ]] || { echo 'Target must be absolute and outside source' >&2; exit 2; }
AVAILABLE=$(df -Pk "$SOURCE" | awk 'NR==2 {print $4}')
(( AVAILABLE >= 4194304 )) || { echo 'Less than 4 GiB free' >&2; exit 2; }
cd "$SOURCE"
moon test review --frozen --target js --target-dir "$TARGET"
flock "$MOON_NATIVE_LOCK" moon build cmd/review_decide --frozen --target native --strip -j 1 --target-dir "$TARGET"
python3 "$SOURCE/scripts/verify-decision-form.py" "$TARGET/native/debug/build/cmd/review_decide/review_decide.exe" "$SOURCE"
