#!/usr/bin/env bash
# Runs round.py (beside this script) with the first Python 3 that actually runs.
#   bash round.sh [--dir DATA_DIR] <command> ...
# Probes python3, then python. A zero-length file (the Windows Store alias stub) or a
# candidate that cannot run a trivial program is skipped. Exits 2 when none runs.
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for name in python3 python; do
  candidate=$(command -v "$name" 2>/dev/null) || continue
  [[ -s "$candidate" ]] || continue
  "$candidate" -c "import sys; sys.exit(0)" >/dev/null 2>&1 || continue
  # shellcheck disable=SC2093  # exec on the first candidate that runs is the point of the loop
  exec "$candidate" "$here/round.py" "$@"
done
echo "missing prerequisite: python3 (no python3 or python on PATH runs)" >&2
exit 2
