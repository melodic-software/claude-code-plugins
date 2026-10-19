#!/usr/bin/env bash
# Tests for tidy-route.sh. Each case builds a throwaway repository, changes its
# work tree and checks the routing. Expected lines come from the routing rules
# in the script's header and in docs/conventions/pr-pipeline/pr-run-activity.md
# ("In-run tidy"): one area and at most --max-changed-lines added plus deleted
# lines run the passes; a docs-only diff runs only the markdown passes;
# instruction surfaces, .github/ and .changes/ are never a pass's file.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/tidy-route.sh"
# shellcheck source=test-git-helpers.sh
. "$SELF_DIR/test-git-helpers.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASSES="$TMP_ROOT/passes.tsv"
printf '%s\t%s\t%s\n' \
  code simplify "" \
  code code-tidying:dissolve-comments "safe --added-since HEAD" \
  markdown ai-slop:audit fix >"$PASSES"

# mk_repo: a committed tree spanning the path classes the cases touch; prints its path.
mk_repo() {
  local dir
  dir="$(mktemp -d "$TMP_ROOT/repo-XXXXXX")" || return 1
  mkdir -p "$dir/plugins/foo/scripts" "$dir/plugins/foo/skills/s/scripts" "$dir/plugins/bar" \
    "$dir/docs" "$dir/.github/scripts"
  printf 'echo a\n' >"$dir/plugins/foo/scripts/a.sh"
  printf '# Foo\n' >"$dir/plugins/foo/README.md"
  printf 'skill\n' >"$dir/plugins/foo/skills/s/SKILL.md"
  printf 'echo t\n' >"$dir/plugins/foo/skills/s/scripts/t.sh"
  printf 'echo x\n' >"$dir/plugins/bar/x.sh"
  printf '# Doc\n' >"$dir/docs/d.md"
  printf 'export {};\n' >"$dir/.github/scripts/x.mjs"
  git_init_test_repo "$dir" >/dev/null || return 1
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base >/dev/null || return 1
  printf '%s\n' "$dir"
}

# lines <file> <n>: appends n lines.
lines() {
  local i
  for ((i = 0; i < $2; i++)); do printf 'echo %d\n' "$i" >>"$1"; done
}

route() {
  OUT="$(cd "$1" && bash "$SCRIPT" --max-changed-lines "${2:-10}" --passes "$PASSES" 2>&1)"
  STATUS=$?
}

expect() {
  local name="$1" want="$2"
  if [[ $STATUS -eq 0 && $OUT == "$want" ]]; then
    pass "$name"
  else
    bad "$name" "exit $STATUS, got:"$'\n'"$OUT"$'\n'"want:"$'\n'"$want"
  fi
}

repo="$(mk_repo)"
route "$repo"
expect "an unchanged tree skips as empty" "route: skip empty"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 2
printf 'more\n' >>"$repo/plugins/foo/README.md"
mkdir -p "$repo/.changes/foo"
printf -- '---\nbump: patch\n' >"$repo/.changes/foo/x.md"
route "$repo"
expect "one plugin's small diff runs every pass on its files, the fragment counted but never passed" "route: run
scope: code, files 3, lines 5, area plugins/foo
run: /simplify plugins/foo/scripts/a.sh
run: /code-tidying:dissolve-comments safe --added-since HEAD plugins/foo/scripts/a.sh
run: /ai-slop:audit fix plugins/foo/README.md"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 1
lines "$repo/plugins/bar/x.sh" 1
route "$repo"
expect "two plugins skip as two areas" "route: skip areas 2: plugins/bar plugins/foo"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 10
route "$repo" 10
expect "a diff of exactly the cutoff runs" "route: run
scope: code, files 1, lines 10, area plugins/foo
run: /simplify plugins/foo/scripts/a.sh
run: /code-tidying:dissolve-comments safe --added-since HEAD plugins/foo/scripts/a.sh"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 10
printf 'gone\n' >"$repo/plugins/foo/scripts/a.sh"
lines "$repo/plugins/foo/scripts/a.sh" 9
route "$repo" 10
expect "added plus deleted lines over the cutoff skip" "route: skip lines 11 over 10"

repo="$(mk_repo)"
printf 'more\n' >>"$repo/docs/d.md"
route "$repo"
expect "a docs-only diff runs only the markdown passes" "route: run
scope: docs-only, files 1, lines 1, area docs
run: /ai-slop:audit fix docs/d.md"

repo="$(mk_repo)"
printf 'more\n' >>"$repo/plugins/foo/skills/s/SKILL.md"
lines "$repo/plugins/foo/skills/s/scripts/t.sh" 1
route "$repo"
expect "a skill's files are never a pass's files" "route: skip no-targets"

repo="$(mk_repo)"
lines "$repo/.github/scripts/x.mjs" 1
route "$repo"
expect "a .github file is never a pass's file" "route: skip no-targets"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 1
lines "$repo/plugins/foo/scripts/new.sh" 2
route "$repo"
expect "a new file runs dissolve-comments without --added-since, since every line is added" "route: run
scope: code, files 2, lines 3, area plugins/foo
run: /simplify plugins/foo/scripts/a.sh
run: /simplify plugins/foo/scripts/new.sh
run: /code-tidying:dissolve-comments safe --added-since HEAD plugins/foo/scripts/a.sh
run: /code-tidying:dissolve-comments safe plugins/foo/scripts/new.sh"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 1
lines "$repo/plugins/foo/scripts/-x.sh" 1
route "$repo"
expect "a name that would read as an option is counted but never passed" "route: run
scope: code, files 2, lines 2, area plugins/foo
run: /simplify plugins/foo/scripts/a.sh
run: /code-tidying:dissolve-comments safe --added-since HEAD plugins/foo/scripts/a.sh"

repo="$(mk_repo)"
lines "$repo/plugins/foo/scripts/a.sh" 1
ln -s ../skills/s/SKILL.md "$repo/plugins/foo/scripts/link.md"
route "$repo"
expect "a symbolic link is never a pass's file, whatever it is named" "route: run
scope: code, files 2, lines 1, area plugins/foo
run: /simplify plugins/foo/scripts/a.sh
run: /code-tidying:dissolve-comments safe --added-since HEAD plugins/foo/scripts/a.sh"

repo="$(mk_repo)"
mkdir "$repo/a"$'\n'"run: x"
printf 'x\n' >"$repo/a"$'\n'"run: x/n.md"
lines "$repo/plugins/foo/scripts/a.sh" 1
route "$repo"
expect "an area name that could forge an output line prints as unprintable" "route: skip areas 2: <unprintable>"

repo="$(mk_repo)"
OUT="$(cd "$repo" && bash "$SCRIPT" --passes "$PASSES" 2>&1)"
STATUS=$?
if [[ $STATUS -eq 2 && $OUT == usage:* ]]; then pass "a missing cutoff is a usage error"; else bad "a missing cutoff is a usage error" "exit $STATUS: $OUT"; fi

OUT="$(cd "$TMP_ROOT" && bash "$SCRIPT" --max-changed-lines 10 --passes "$PASSES" 2>&1)"
STATUS=$?
if [[ $STATUS -eq 2 ]]; then pass "outside a work tree exits 2"; else bad "outside a work tree exits 2" "exit $STATUS: $OUT"; fi

test_harness::report
