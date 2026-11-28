#!/usr/bin/env bash
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
for name in python3 python; do
  candidate=$(command -v "$name" 2>/dev/null) || continue
  [[ -s "$candidate" ]] || continue
  "$candidate" -I -c "import sys; sys.exit(0)" >/dev/null 2>&1 || continue
  # -I: no PYTHON* variables, no user site, no current folder on sys.path (share.py adds its own).
  # shellcheck disable=SC2093  # exec on the first candidate that runs is the point of the loop
  exec "$candidate" -I "$here/share.py" "$@"
done
echo "missing prerequisite: python3 (no python3 or python on PATH runs)" >&2
exit 2
