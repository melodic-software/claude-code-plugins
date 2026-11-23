#!/usr/bin/env bash
set -uo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  printf 'check-skill-links: python3 is not on PATH\n' >&2
  exit 2
fi
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
root="${1:-$(cd "$here/.." && pwd)}" || exit 2
exec python3 -I "$here/check-skill-links.py" "$root"
