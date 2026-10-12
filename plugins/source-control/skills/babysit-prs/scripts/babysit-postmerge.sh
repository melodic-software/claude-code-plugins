#!/usr/bin/env bash
# Runs the post-merge check (babysit_postmerge.py) under a working Python 3.11+.
# Read-only by default: it reads GitHub and prints a JSON verdict. Only
# --remediate writes (the one attribution re-run, a full-run dispatch when no
# run covers an unverified merge, dequeue, the demotion issue).
#
#   babysit-postmerge.sh --repo <owner/repo> --agent-identity <login>
#     [--since <ISO 8601>] [--branch <name>] [--self-login <login>]...
#     [--remediate | --preflight]
#
# --preflight checks only that the session acts as the identity and holds no
# other account (the merge gate's identity and credential rules), and that this
# checkout pushes over https to github.com through gh's credential helper alone;
# it reads git config, never writes, and exits 0 or 2.
#
# --since defaults to the merge gate's floor (the enabling config commit, or the
# newest human close of a demotion record when later); --branch to the
# repository's default branch.
# Exit: 0 no failure and every auto-merge verified, 1 a failure, 2 usage or a
# refused identity, 3 unreadable or no Python, 4 a write failed, 5 an auto-merge
# not yet verified. Only 0 lets a merge proceed.
set -euo pipefail
export PYTHONUTF8=1
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=babysit-python.sh
. "$scripts/babysit-python.sh"
babysit_python "$scripts/babysit_postmerge.py" "$@"
