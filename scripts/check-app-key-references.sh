#!/usr/bin/env bash
# Check that no workflow or action references the lanes App key or mints as the lanes App.
#
#   scripts/check-app-key-references.sh          discover: list every offender
#   scripts/check-app-key-references.sh --check  same, explicit form matching the
#                                                sibling gates (exit 1 on any offender)
#
# Scope: .github/workflows/** and .github/actions/** lines naming
# AUTOMATION_LANES_APP_PRIVATE_KEY, app-private-key or AUTOMATION_LANES_APP_CLIENT_ID
# (case-insensitive); other Apps' mints and docs are out of scope.
#
# WHY. Lane jobs get their App token from the lanes token broker, which holds
# the key; a key referenced anywhere in a workflow run must be assumed to reach
# every job of that run, and a lanes client id in a workflow means a mint that
# bypasses the broker. Contract: docs/conventions/pr-pipeline/pr-run-activity.md,
# "The lane token broker"; ADR 0058.
#
# Output follows the check-script contract (README.md, "The check-script
# contract"): one `path:line: finding` per offender on stderr, the clean-run
# statement on stdout. Exit: 0 clean, 1 any offender, 2 usage or environment.
set -euo pipefail

case "${1:-}" in
'' | --check) ;;
*)
  printf 'usage: %s [--check]\n' "${0##*/}" >&2
  exit 2
  ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
cd "$ROOT" || exit 2

pattern='automation_lanes_app_private_key|app-private-key|automation_lanes_app_client_id'
dirs=()
for dir in .github/workflows .github/actions; do
  [[ -d "$dir" ]] && dirs+=("$dir")
done
if [[ "${#dirs[@]}" -eq 0 ]]; then
  printf 'check-app-key-references: neither .github/workflows nor .github/actions exists\n' >&2
  exit 2
fi

rc=0
hits=$(grep -rnIiE -- "$pattern" "${dirs[@]}") || rc=$?
if [[ "$rc" -gt 1 ]]; then
  printf 'check-app-key-references: grep failed (exit %s)\n' "$rc" >&2
  exit 2
fi
if [[ -n "$hits" ]]; then
  while IFS= read -r hit; do
    printf '%s: references the lanes App key or client id\n' "${hit%%:*}:$(cut -d: -f2 <<<"$hit")" >&2
  done <<<"$hits"
  exit 1
fi
printf 'check-app-key-references: no workflow or action references the lanes App key or client id\n'
