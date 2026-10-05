#!/usr/bin/env bash
# Check that no workflow run reaching pr-run-activity-read.yml can hold the
# lanes App private key, and that the read workflow requests no OIDC token.
#
#   scripts/check-read-caller-keys.sh          discover: list every offender
#   scripts/check-read-caller-keys.sh --check  same, explicit form matching the
#                                              sibling gates (exit 1 on any offender)
#
# The rule: parse every workflow under .github/workflows/ and build the call
# graph of this repository's workflows (a job-level `uses:` in `./` or
# `melodic-software/claude-code-plugins/...@ref` form, any case). Walk up from
# pr-run-activity-read.yml to every workflow whose run can reach it, then down
# through every reusable workflow those runs call. In every file of such a run,
# each parsed mapping key and string value (`#` lines inside `run:` blocks
# included) is checked:
#   - no `AUTOMATION_LANES_APP_PRIVATE_KEY` or `app-private-key` in a key or
#     value, and no `private-key` key (keys compared after parsing,
#     case-insensitively);
#   - no `secrets: inherit`;
#   - every `secrets` reference in a `${{ }}` expression is `secrets.<name>`
#     with `<name>` on the allowlist `claude_code_oauth_token`, `github_token`
#     (lower-cased, `-` read as `_`); `toJSON(secrets)`, `secrets[...]` and
#     bare `secrets` fail.
# The read workflow itself must also not name `id-token`. A missing read
# workflow, or a workflow that does not parse, is an offender, so neither a
# rename nor a syntax error turns the check into a silent pass.
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
