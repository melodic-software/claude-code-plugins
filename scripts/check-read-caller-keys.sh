#!/usr/bin/env bash
# Check that no workflow run reaching pr-run-activity-read.yml can hold the
# lanes App private key, and that the read workflow requests no OIDC token.
#
#   scripts/check-read-caller-keys.sh          discover: list every offender
#   scripts/check-read-caller-keys.sh --check  same, explicit form matching the
#                                              sibling gates (exit 1 on any offender)
#
# The rule: every workflow under .github/workflows/ that calls
# ./.github/workflows/pr-run-activity-read.yml, and every repository-local
# reusable workflow that caller reaches through `uses: ./.github/workflows/...`,
# must not reference the App key: no `AUTOMATION_LANES_APP_PRIVATE_KEY`, no
# `app-private-key` and no `private-key:` on a non-comment line. The read
# workflow itself must also not name `id-token`. A missing read workflow is an
# offender, so a rename cannot turn the check into a silent pass.
#
# WHY. GitHub scrubs secrets per workflow run, not per job: a caller plus every
# reusable workflow it calls is one run, and a secret referenced anywhere in it
# must be assumed delivered to every job, including the read job that runs PR
# head code. So a lane goes live with head-code read activities only when its
# caller file references no App key at all; a lane mixing read and write
# activities waits for the token broker. Contract:
# docs/conventions/pr-pipeline/pr-run-activity.md, "Secrets and the two files".
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `path:line: finding` per offender on stderr, the clean-run
# statement on stdout. Exit: 0 clean, 1 any offender, 2 usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

WORKFLOWS=.github/workflows
READ_WORKFLOW="$WORKFLOWS/pr-run-activity-read.yml"
KEY_PATTERN='AUTOMATION_LANES_APP_PRIVATE_KEY|app-private-key|private-key:'
USES_LOCAL='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*["'\'']?\./\.github/workflows/'

# non_comment_matches <pattern> <file>: `line:text` for each match outside a
# whole-line comment.
non_comment_matches() {
  grep -nE -- "$1" "$2" | grep -vE '^[0-9]+:[[:space:]]*#' || true
}

# local_callees <file>: the repository-local reusable workflows it calls.
local_callees() {
  grep -E -- "$USES_LOCAL" "$1" |
    sed -E 's#.*\./\.github/workflows/([^"'\''@[:space:]#]+).*#.github/workflows/\1#' || true
}

offenders=()

if [[ ! -f "$READ_WORKFLOW" ]]; then
  offenders+=("$READ_WORKFLOW: missing; the read-caller key check has nothing to anchor on")
else
  while IFS= read -r hit; do
    [[ -n "$hit" ]] && offenders+=("$READ_WORKFLOW:${hit%%:*}: the read workflow names id-token")
  done < <(non_comment_matches 'id-token' "$READ_WORKFLOW")
fi

callers=()
if [[ -d "$WORKFLOWS" ]]; then
  for file in "$WORKFLOWS"/*.yml "$WORKFLOWS"/*.yaml; do
    [[ -f "$file" && "$file" != "$READ_WORKFLOW" ]] || continue
    # shellcheck disable=SC2310  # local_callees cannot fail; it ends in || true
    if grep -qxF "$READ_WORKFLOW" < <(local_callees "$file"); then
      callers+=("$file")
    fi
  done
fi

# Every file in one caller's run: the caller, then each local reusable workflow
# it reaches, breadth-first, each visited once.
for caller in ${callers+"${callers[@]}"}; do
  run=("$caller")
  for ((i = 0; i < ${#run[@]}; i++)); do
    while IFS= read -r callee; do
      [[ -n "$callee" && -f "$callee" ]] || continue
      seen=""
      for one in "${run[@]}"; do [[ "$one" == "$callee" ]] && seen=1; done
      [[ -n "$seen" ]] || run+=("$callee")
    done < <(local_callees "${run[i]}")
  done
  for file in "${run[@]}"; do
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      if [[ "$file" == "$caller" ]]; then
        offenders+=("$file:${hit%%:*}: calls $READ_WORKFLOW and references the App key")
      else
        offenders+=("$file:${hit%%:*}: references the App key in the run of $caller, which calls $READ_WORKFLOW")
      fi
    done < <(non_comment_matches "$KEY_PATTERN" "$file")
  done
done

if ((${#offenders[@]} == 0)); then
  printf 'check-read-caller-keys: no run that calls %s references the App key (%d caller(s)).\n' \
    "$READ_WORKFLOW" "${#callers[@]}"
  exit 0
fi

printf '%s\n' "${offenders[@]}" | sort -u >&2
printf 'check-read-caller-keys: %d offender(s); a lane that calls the read workflow references no App key, and a lane mixing read and write activities waits for the token broker (see the header of %s).\n' \
  "${#offenders[@]}" "scripts/${0##*/}" >&2
exit 1
