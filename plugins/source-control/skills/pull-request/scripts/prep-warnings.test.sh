#!/usr/bin/env bash
# Regression tests for prep-warnings.sh against a fixture repository. Expected
# lines come from the rules prep_warnings.py states: a cut to an existing
# SKILL.md or agent body warns unless its eval home changes too, and a path in
# babysit_risk.HIGH_FLOOR, the configured denied paths or a manifest warns.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/prep-warnings.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

# shellcheck source=../../babysit-prs/scripts/babysit-python.sh
source "$SCRIPT_DIR/../../babysit-prs/scripts/babysit-python.sh"
_babysit_probe_python py -3 || _babysit_probe_python python3 || _babysit_probe_python python ||
  skip_suite "no Python 3.11+ interpreter"

TEST_TMPDIR="$(native_mktemp_dir)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
REPO="$TEST_TMPDIR/repo"

g() { git -C "$REPO" -c user.name=test -c user.email=test@example.com "$@"; }

write() {
  mkdir -p "$(dirname "$REPO/$1")"
  printf '%s\n' "${@:2}" >"$REPO/$1"
}

git init -q "$REPO"
g symbolic-ref HEAD refs/heads/main
write plugins/p/skills/s/SKILL.md "# s" "one" "two"
write plugins/p/skills/s/evals/evals.json "{}"
write plugins/p/agents/a.md "# a" "one" "two"
write plugins/p/.claude-plugin/plugin.json '{"name": "p"}'
write .github/workflows/pr-require-checks.yml "name: checks"
write docs/conventions/pr-pipeline.yaml "merge:" "  diff-check:" '    denied-paths: ["notes/**"]'
write notes/n.md "n"
write README.md "readme"
g add -A
g commit -q -m base

# branch <name>: a fresh branch off main with a clean tree.
branch() {
  g checkout -q -f main
  g clean -fdq
  g checkout -q -b "$1"
}

commit() {
  g add -A
  g commit -q -m "$1"
}

run() { bash "$SCRIPT" --dir "$REPO" --base main; }

branch skill-cut
write plugins/p/skills/s/SKILL.md "# s" "one"
commit cut
out=$(run)
assert_exit "a skill cut is still a read" 0 "$?"
assert_contains "a skill cut with no eval change warns, naming the file" "$out" \
  "skill-cut plugins/p/skills/s/SKILL.md:"
assert_contains "the warning names the eval home" "$out" "plugins/p/skills/s/evals/"

branch skill-cut-with-evals
write plugins/p/skills/s/SKILL.md "# s" "one"
write plugins/p/skills/s/evals/evals.json '{"evals": []}'
commit cut
out=$(run)
assert_exit "the same cut with an eval change exits 0" 0 "$?"
assert_not_contains "the same cut with an eval change does not warn" "$out" "skill-cut"

branch skill-cut-deleting-evals
write plugins/p/skills/s/SKILL.md "# s" "one"
g rm -q plugins/p/skills/s/evals/evals.json
commit cut
assert_contains "a cut whose eval change is a deletion still warns" "$(run)" \
  "skill-cut plugins/p/skills/s/SKILL.md:"

branch workflow
write .github/workflows/pr-require-checks.yml "name: checks" "on: push"
commit workflow
out=$(run)
assert_contains "an edit to pr-require-checks.yml warns, naming the file" "$out" \
  "protected-path .github/workflows/pr-require-checks.yml:"
assert_contains "the warning names the floor glob" "$out" \
  "high-path:.github/workflows/pr-require-checks.yml"

branch neither
write README.md "readme" "more"
commit readme
out=$(run)
assert_exit "a branch touching neither exits 0" 0 "$?"
assert_silent "a branch touching neither prints nothing" "$out"

branch skill-add
write plugins/p/skills/t/SKILL.md "# t"
write plugins/p/skills/s/SKILL.md "# s" "one" "two" "three"
commit add
out=$(run)
assert_exit "an added skill exits 0" 0 "$?"
assert_silent "an added skill and an added line do not warn" "$out"

branch agent-cut
write plugins/p/agents/a.md "# a"
commit cut
assert_contains "an agent cut with no plugin eval change warns" "$(run)" \
  "skill-cut plugins/p/agents/a.md:"
write plugins/p/evals/case/eval.json "{}"
commit evals
out=$(run)
assert_exit "an agent cut with a plugin eval change exits 0" 0 "$?"
assert_not_contains "an agent cut with a plugin eval change does not warn" "$out" "skill-cut"

branch uncommitted
write plugins/p/skills/s/SKILL.md "# s"
write notes/new.md "new"
out=$(run)
assert_contains "an uncommitted cut counts" "$out" "skill-cut plugins/p/skills/s/SKILL.md:"
assert_contains "an untracked file under a configured denied path warns" "$out" \
  "protected-path notes/new.md: the guarded merge holds it for a person (high-path:notes/**)"
out=$(bash "$SCRIPT" --dir "$REPO/plugins" --base main)
assert_contains "run from a subdirectory, an untracked file elsewhere still warns" "$out" \
  "protected-path notes/new.md:"

branch unsafe-path
write "plugins/p/my file.md" "x"
commit unsafe
assert_contains "a path with an unsafe segment warns with the merge's unsafe-path code" "$(run)" \
  "protected-path plugins/p/my file.md: the guarded merge holds it for a person (high-path:**)"

branch manifest
write plugins/p/.claude-plugin/plugin.json '{"name": "p", "version": "1.0.0"}'
commit manifest
assert_contains "a plugin manifest change warns" "$(run)" \
  "protected-path plugins/p/.claude-plugin/plugin.json:"

branch unreadable-config
write docs/conventions/pr-pipeline.yaml "merge:" "  diff-check:" '    denied-paths: ["notes/**"'
commit config
g checkout -q -b unreadable-child
write notes/n.md "changed"
commit notes
out=$(bash "$SCRIPT" --dir "$REPO" --base unreadable-config)
assert_exit "an unreadable pipeline file is still a read" 0 "$?"
assert_contains "an unreadable pipeline file is reported" "$out" \
  "merge.diff-check.denied-paths not checked"
assert_not_contains "no configured path matches when it is unread" "$out" "protected-path notes/n.md"

bash "$SCRIPT" --dir "$REPO" >/dev/null 2>&1
assert_exit "a missing --base exits 1" 1 "$?"
bash "$SCRIPT" --dir "$REPO" --base -x >/dev/null 2>&1
assert_exit "a --base that reads as an option exits 1" 1 "$?"
bash "$SCRIPT" --dir "$REPO" --base no-such-ref >/dev/null 2>&1
assert_exit "a base that does not resolve exits 2" 2 "$?"

[[ $FAILED -eq 0 ]] || exit 1
