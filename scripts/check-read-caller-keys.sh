#!/usr/bin/env bash
# Check that no workflow run reaching pr-run-activity-read.yml can hold the
# lanes App private key, and that the read workflow requests an OIDC token
# only in its broker-check job.
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
#     with `<name>` (lower-cased, `-` read as `_`) in the shared set
#     `fallback_claude_code_oauth_token`, `claude_code_oauth_token`,
#     `claude_api_key`, `github_token`, or, in a workflow whose run reaches
#     the read workflow, in that workflow's own entry of the caller map:
#     `pr-refine.yml` and `pr-unblock.yml` may also name
#     `pr_unblock_claude_code_oauth_token` and `pr_unblock_claude_api_key`,
#     `work-resolve-issue.yml` `issue_lane_claude_code_oauth_token` and
#     `issue_lane_claude_api_key`; `toJSON(secrets)`, `secrets[...]` and bare
#     `secrets` fail;
#   - one exception to both rules above, the scan-carrier key: the read
#     workflow's `scan` job may hold one step that uses
#     `./.base/.github/actions/open-lane-output` with
#     `private-key: ${{ secrets.scan-carrier-private-key }}`, exactly, and a
#     job that calls the read workflow may pass
#     `scan-carrier-private-key: ${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}`,
#     exactly, in its `secrets` map; that secret anywhere else fails;
#   - no `environment` key, except `environment: pr-pipeline-scan-carrier` on
#     the read workflow's `scan` job.
# No file of such a run sets `permissions: write-all`. The read workflow
# itself must set top-level `permissions: {}` and a permissions map on every
# job, may name `id-token` only inside its `broker-check` job, which runs no PR
# head code, and that job must be `steps` (not a reusable call) whose
# `actions/checkout` steps take only `ref`, `path` and `persist-credentials`,
# with `ref: ${{ github.event.repository.default_branch }}`. A missing
# read workflow, a workflow that does not parse, or a workflow whose run
# reaches the read workflow with no entry in the caller map is an offender, so
# neither a rename, a syntax error nor a new caller turns the check into a
# silent pass.
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
