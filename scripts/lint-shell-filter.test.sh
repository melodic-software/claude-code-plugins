#!/usr/bin/env bash
# Pins what the `lint_shell` filter group of .github/workflows/pr-require-checks.yml
# matches: a change to any input of a `lint-shell` gate starts the lane, and a
# change no gate reads does not. The detect-changes action matches each pattern
# as a root-anchored gitignore rule, so `git check-ignore --no-index` against
# the group, written as a .gitignore, answers the same question.
# test-scope: .github/workflows/pr-require-checks.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"
# shellcheck source=test-git-helpers.sh
. "$ROOT/scripts/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

awk '/^            lint_shell:$/ { on = 1; next }
  on && /^              [^ ]/ { sub(/^ +/, ""); print; next }
  on { exit }' "$WORKFLOW" >"$TMP_ROOT/patterns"
if [[ ! -s "$TMP_ROOT/patterns" ]]; then
  fail "no lint_shell filter group in $WORKFLOW"
  test_harness::report
  exit 1
fi

repo="$TMP_ROOT/repo"
mkdir -p "$repo"
git_test_config "$repo" init -q
cp "$TMP_ROOT/patterns" "$repo/.gitignore"

# matches <path>: the group matches a change to <path>.
matches() { git_test_config "$repo" check-ignore --no-index -q -- "$1"; }

for p in \
  plugins/harness-ops/reference/x.md \
  plugins/alpha/skills/s/reference/y.md \
  plugins/alpha/docs/notes.md \
  plugins/alpha/.claude-plugin/plugin.json \
  plugins/alpha/config/extra-hooks.json \
  plugins/alpha/config/custom-hooks.conf \
  plugins/alpha/hooks/hooks.json \
  plugins/alpha/skills/s/SKILL.md \
  scripts/check-shell-portability.sh \
  lib/x.sh \
  .github/workflows/pr-require-checks.yml; do
  if matches "$p"; then ok "starts lint-shell: $p"; else fail "should start lint-shell: $p"; fi
done

for p in \
  docs/plugin-philosophy.md \
  README.md \
  .github/actionlint.yaml \
  src/App.cs \
  scripts/suite-seconds.txt; do
  if matches "$p"; then fail "should not start lint-shell: $p"; else ok "does not start lint-shell: $p"; fi
done

test_harness::report
