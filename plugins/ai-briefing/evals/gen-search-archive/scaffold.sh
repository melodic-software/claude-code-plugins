#!/usr/bin/env bash
# One archived briefing (meeting 5) in archives/, copied by name from the shared fixtures.
set -euo pipefail
set -o noclobber
here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -e archives ]]; then
  echo "refusing to scaffold: ${here}/archives exists" >&2
  exit 3
fi
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd -P)"
mkdir archives
cat "${fixtures}/gen-archive-meeting-5.md" >archives/meeting-5.md
