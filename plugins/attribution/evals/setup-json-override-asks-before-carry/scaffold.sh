#!/usr/bin/env bash
# A gitignored personal override docs/conventions/attribution.local.yaml (judge_samples 5) and
# the retired .claude/attribution.local.json (attribution-r004: judge_samples 3,
# trigger_less_stamp_check true). No convention-home pointer, no team layer.
set -euo pipefail

here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
# The eval workspace sits inside the run's temporary home, itself a repository: allow only that one.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  tmp="$(cd "${TMPDIR:-/nonexistent}" 2>/dev/null && pwd -P || true)"
  if [[ "${top}" == "${here}" ]]; then
    echo "refusing to scaffold: ${here} is already a repository" >&2
    exit 3
  fi
  run="$(dirname "${tmp:-/}")"
  if [[ -z "${tmp}" || "$(basename "${tmp}")" != tmp || "$(basename "${run}")" != claude-eval-* || "${top}" != "${run}/home" || "${here}/" != "${top}/"* ]]; then
    echo "refusing to scaffold inside ${top}, a repository outside TMPDIR (${TMPDIR:-unset})" >&2
    exit 3
  fi
fi
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES

git init -q -b main .
printf '# Widget service\n\nInternal notes for the widget service.\n' >README.md
printf '%s\n' '*.local.yaml' '.claude/*.local.json' >.gitignore
mkdir -p docs/conventions
printf 'judge_samples: 5\n' >docs/conventions/attribution.local.yaml
mkdir -p .claude
cat >.claude/attribution.local.json <<'JSON'
{
  "judge_samples": 3,
  "trigger_less_stamp_check": true
}
JSON
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
