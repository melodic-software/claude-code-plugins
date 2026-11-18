#!/bin/sh
# Run with sh, never bash by name: on Windows that can be System32's WSL launcher.
# shellcheck shell=sh
event=$1 job=$2 script=$3
shift 3
sh "$script" "$@" && exit 0
rc=$?
case "$job" in
  guardrails-remote-pre-commit-content | guardrails-remote-pre-push-content) exit "$rc" ;;
  *) ;;
esac
printf '%s\n' \
  "$job failed (exit $rc): fix what it reports above." \
  "Only if the job itself is broken, skip it in this clone with an untracked lefthook-local.yml (list it in .git/info/exclude):" \
  "$event:" \
  "  jobs:" \
  "    - name: $job" \
  "      skip: true" \
  "Run lefthook install once the fix is on main, then delete the skip:" \
  "https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md#when-a-remote-job-breaks" >&2
exit "$rc"
