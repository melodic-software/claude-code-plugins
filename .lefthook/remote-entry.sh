#!/bin/sh
# Run with sh, never bash by name: on Windows that can be System32's WSL launcher.
# shellcheck shell=sh
event=$1 job=$2 script=$3
shift 3
sh "$script" "$@" && exit 0
rc=$?
group=
case "$job" in
  guardrails-remote-pre-commit-content | guardrails-remote-pre-push-content) exit "$rc" ;;
  bash-format-remote-format | bash-format-remote-lint) group=bash-format-remote ;;
  javascript-format-remote-format | javascript-format-remote-lint) group=javascript-format-remote ;;
  markdown-format-remote-format | markdown-format-remote-lint) group=markdown-format-remote ;;
  powershell-format-remote-format | powershell-format-remote-lint) group=powershell-format-remote ;;
  python-format-remote-format | python-format-remote-lint) group=python-format-remote ;;
  *) ;;
esac
if [ -n "$group" ]; then
  set -- "    - name: $group" "      group:" "        jobs:" "          - name: $job" "            skip: true"
else
  set -- "    - name: $job" "      skip: true"
fi
printf '%s\n' \
  "$job failed (exit $rc): fix what it reports above." \
  "Only if the job itself is broken, skip it in this clone with an untracked lefthook-local.yml (list it in .git/info/exclude):" \
  "$event:" \
  "  jobs:" \
  "$@" \
  "Run lefthook install once the fix is on main, then delete the skip:" \
  "https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/check-placement/adopting-git-hooks.md#when-a-remote-job-breaks" >&2
exit "$rc"
