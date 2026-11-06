#!/usr/bin/env bash
# workspace.sh <repo|override|disabled>: makes the eval's empty workspace (the current directory) a
# git repository with no multi-agent layer, and then:
#   repo      nothing more
#   override  .claude/multi-agent.local.yaml setting roles.worker.model to a full model id
#   disabled  .claude/settings.json with "disableWorkflows": true
# The runner sets HOME to the run's temporary home for a scaffold script
# (https://code.claude.com/docs/en/plugin-evals, "Set up fixtures and mocks"). The guards refuse
# the account's real home, the root, the home directory, a workspace that is already a repository,
# any enclosing repository other than the run's home (claude-eval-*/home, beside TMPDIR at
# claude-eval-*/tmp, as repo-hygiene's fabrikam-repo.sh allows), and any file that already exists.
set -euo pipefail

refuse() {
  echo "refusing: $1" >&2
  exit 3
}

mode="${1:-}"
case "${mode}" in
repo | override | disabled) ;;
*) refuse "unknown mode '${mode}' (repo, override or disabled)" ;;
esac

[[ -n "${HOME:-}" && -d "$HOME" ]] || refuse "HOME is unset or not a directory"
user=$(id -un)
if command -v getent >/dev/null 2>&1; then
  real_home=$(getent passwd "$user" | cut -d: -f6)
elif command -v dscl >/dev/null 2>&1; then
  real_home=$(dscl . -read "/Users/$user" NFSHomeDirectory | awk '{print $2}')
else
  refuse "cannot look up the account's real home to compare against"
fi
[[ -n "$real_home" ]] || refuse "the account's real home did not resolve"
[[ "$(cd "$HOME" && pwd -P)" != "$(cd "$real_home" && pwd -P)" ]] || refuse "HOME is the account's real home: $HOME"

here="$(pwd -P)"
case "${here}" in
/ | "$(cd "$HOME" && pwd -P)") refuse "will not scaffold in ${here}" ;;
*) ;;
esac
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  [[ "${top}" != "${here}" ]] || refuse "${here} is already a repository"
  tmp="$(cd "${TMPDIR:-/nonexistent}" 2>/dev/null && pwd -P || true)"
  run="$(dirname "${tmp:-/}")"
  if [[ -z "${tmp}" || "$(basename "${tmp}")" != tmp || "$(basename "${run}")" != claude-eval-* || "${top}" != "${run}/home" || "${here}/" != "${top}/"* ]]; then
    refuse "${here} is inside ${top}, a repository outside TMPDIR (${TMPDIR:-unset})"
  fi
fi
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES

for f in README.md .claude/multi-agent.local.yaml .claude/settings.json; do
  [[ ! -e "${f}" ]] || refuse "${here}/${f} already exists"
done
git init -q -b main
[[ "$(git rev-parse --show-toplevel)" == "${here}" ]] || refuse "git did not create a repository at ${here}"
git config core.excludesFile /dev/null
printf '# demo\n' >README.md
case "${mode}" in
override)
  mkdir -p .claude
  printf 'schema: 1\nroles:\n  worker:\n    model: claude-opus-5-5\n' >.claude/multi-agent.local.yaml
  ;;
disabled)
  mkdir -p .claude
  printf '{\n  "disableWorkflows": true\n}\n' >.claude/settings.json
  ;;
*) ;;
esac
