#!/usr/bin/env bash
set -euo pipefail
export PYTHONUTF8=1
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=babysit-python.sh
. "$scripts/babysit-python.sh"
babysit_python "$scripts/babysit_postmerge.py" "$@"
