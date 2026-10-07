#!/usr/bin/env bash
# Self-contained tests for list-targets.sh and list-pointers.sh --json, the two
# scripts that build the drift-audit workflow's args. Assertions match
# substrings, so no JSON tool is needed.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG CLAUDE_PROJECT_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

FAILED=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() {
  FAILED=1
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_lacks() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

# ---- list-targets.sh ----
R="$T/repo"
mkdir -p "$R/plugins/p/skills/s" "$R/docs/upstream" "$R/docs/x" "$R/plugins/p/skills/s/evals" "$R/plugins/q"
git -C "$R" init -q
printf 'Run workers on opus at medium effort.\n' >"$R/plugins/p/skills/s/SKILL.md"
printf -- '---\nmodel: sonnet\n---\n' >"$R/plugins/q/agent.md"
# A path with a quote tests the JSON escape; Windows paths cannot hold one, so the
# fixture and its assertion run only where the file system accepts the name.
QUOTE_PATH=0
# Git Bash maps the quote to another character instead of failing, so test the platform.
case "$(uname -s)" in
MINGW* | MSYS* | CYGWIN*) printf 'The Workflow tool caps concurrency.\n' >"$R/docs/x/a_q.md" ;;
*)
  QUOTE_PATH=1
  printf 'The Workflow tool caps concurrency.\n' >"$R/docs/x/a \"q\".md"
  ;;
esac
printf 'Use opus.\n' >"$R/README.md"
printf 'Nothing relevant here.\n' >"$R/docs/x/plain.md"
printf 'Use opus.\n' >"$R/docs/upstream/snapshot.md"
printf 'Use opus.\n' >"$R/plugins/p/CHANGELOG.md"
printf 'Use opus.\n' >"$R/plugins/p/skills/s/evals/case.md"
printf 'Use opus.\n' >"$R/untracked.md"
printf 'Use opus.\n' >"$T/outside.md"
# Plain ln -s copies the file on Windows; ask for a native symlink there.
MSYS=winsymlinks:nativestrict ln -s "$T/outside.md" "$R/docs/x/link.md"
git -C "$R" add plugins docs README.md
out="$("$SCRIPT_DIR/list-targets.sh" --root "$R")"
assert_contains 'groups a plugin by plugins/<name>' "$out" '{"area":"plugins/p","files":["plugins/p/skills/s/SKILL.md"]}'
assert_contains 'a model: frontmatter line is a claim' "$out" '"plugins/q/agent.md"'
if ((QUOTE_PATH)); then
  assert_contains 'escapes a quote in a path' "$out" '"docs/x/a \"q\".md"'
else
  printf 'SKIP: escapes a quote in a path (a Windows path cannot hold a quote)\n'
fi
assert_contains 'top-level files are the (root) area' "$out" '{"area":"(root)","files":["README.md"]}'
for skip in plain.md upstream/snapshot.md CHANGELOG.md evals/case.md untracked.md link.md; do
  assert_lacks "leaves out $skip" "$out" "$skip"
done
for i in $(seq 1 12); do printf 'Use haiku.\n' >"$R/docs/x/f$i.md"; done
git -C "$R" add docs
out="$("$SCRIPT_DIR/list-targets.sh" --root "$R")"
assert_contains 'splits an area past 10 files' "$out" '"area":"docs (2/2)"'
if "$SCRIPT_DIR/list-targets.sh" --root "$T/missing" >/dev/null 2>&1; then
  fail 'a missing root exits non-zero' 'non-zero' '0'
else
  pass 'a missing root exits non-zero'
fi

# ---- list-pointers.sh --json ----
json="$("$SCRIPT_DIR/list-pointers.sh" --json fanout)"
assert_contains 'json starts an array' "$json" '[{"owner":"fanout","key":"pointer","value":"https://'
assert_contains 'json carries the value rows with full keys' "$json" '{"owner":"fanout","key":"fanout.model","value":"opus"}'
assert_lacks 'json for one owner leaves out the others' "$json" '"owner":"worker"'
json="$("$SCRIPT_DIR/list-pointers.sh" --json)"
assert_contains 'json maps a role value to its owner' "$json" '{"owner":"worker","key":"roles.worker.effort","value":'
assert_lacks 'json leaves out the schema row' "$json" '"key":"schema"'
tsv="$("$SCRIPT_DIR/list-pointers.sh" worker)"
assert_contains 'tsv mode is unchanged' "$tsv" "$(printf 'roles.worker.effort\t')"

if ((FAILED)); then
  echo 'list-scripts tests failed.' >&2
  exit 1
fi
echo 'All list-scripts tests passed.'
