#!/usr/bin/env bash
# Check that no workflow run reaching pr-run-activity-read.yml can hold the
# lanes App private key, and that the read workflow requests no OIDC token.
#
#   scripts/check-read-caller-keys.sh          discover: list every offender
#   scripts/check-read-caller-keys.sh --check  same, explicit form matching the
#                                              sibling gates (exit 1 on any offender)
#
# The rule: parse every workflow under .github/workflows/ and build the
# repository-local call graph (`jobs.<id>.uses: ./.github/workflows/...`).
# Walk up from ./.github/workflows/pr-run-activity-read.yml to every workflow
# whose run can reach it, then down through every reusable workflow those runs
# call. No file of such a run may, on a non-comment line, name
# `AUTOMATION_LANES_APP_PRIVATE_KEY`, `app-private-key` or `private-key:`, pass
# `secrets: inherit`, or read secrets by a computed name (`toJSON(secrets)`,
# `secrets[...]`). The read workflow itself must also not name `id-token`. A
# missing read workflow, or a workflow that does not parse, is an offender, so
# neither a rename nor a syntax error turns the check into a silent pass.
#
# WHY. GitHub scrubs secrets per workflow run, not per job: a caller plus every
# reusable workflow it calls is one run, and a secret referenced anywhere in it
# must be assumed delivered to every job, including the read job that runs PR
# head code. So a lane goes live with head-code read activities only when no
# file of its run references the App key; a lane mixing read and write
# activities waits for the token broker. Contract:
# docs/conventions/pr-pipeline/pr-run-activity.md, "Secrets and the two files".
#
# The work is in check-read-caller-keys.mjs beside this file. It parses YAML
# with the `yaml` package installed by
# `npm ci --prefix .github/standards/runner-policy`.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `path:line: finding` per offender on stderr, the clean-run
# statement on stdout. Exit: 0 clean, 1 any offender, 2 usage or environment
# (no node, or the yaml package not installed).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

if ! command -v node >/dev/null 2>&1; then
  printf 'check-read-caller-keys: node is not on PATH\n' >&2
  exit 2
fi
exec node "$SCRIPT_DIR/check-read-caller-keys.mjs"
