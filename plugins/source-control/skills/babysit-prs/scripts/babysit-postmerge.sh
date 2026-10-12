#!/usr/bin/env bash
# Runs the post-merge check (babysit_postmerge.py) under a working Python 3.11+.
# Read-only by default: it reads GitHub and prints a JSON verdict. Only
# --remediate writes (the one attribution re-run, a full-run dispatch when no
# run covers an unverified merge, dequeue, the demotion issue).
#
#   babysit-postmerge.sh --repo <owner/repo> --agent-identity <login> --since <ISO 8601> [--remediate]
#
# Exit: 0 no failure, 1 a failure, 2 usage, 3 unreadable or no Python, 4 a write failed.
set -euo pipefail
export PYTHONUTF8=1
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=babysit-python.sh
. "$scripts/babysit-python.sh"
babysit_python "$scripts/babysit_postmerge.py" "$@"
