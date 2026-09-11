#!/usr/bin/env bash
# Black-box contract test for check-docs-naming.sh.
#
# Self-contained and cwd-independent: builds a throwaway git repository with a
# fixture docs/ tree, runs the checker against it, and asserts on exit code +
# output. Mutates only its own mktemp dir. The SUT resolves the repository root
# relative to its own location, so the fixture tree carries a copy of it under
# scripts/ and every case commits its files so `git ls-files` sees them.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-docs-naming.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# mk_repo <out-var>: a throwaway repo with a committed, rule-abiding docs/ tree.
# The builder assigns through a nameref, which shellcheck cannot follow.
mk_repo() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --git || return 1
  dir="${!1}"
  mkdir -p "$dir/docs/conventions/topic-docs" "$dir/docs/adr"
  printf 'seed\n' >"$dir/docs/README.md"
  printf 'seed\n' >"$dir/docs/plugin-philosophy.md"
  printf 'seed\n' >"$dir/docs/conventions/topic-docs/README.md"
  printf 'seed\n' >"$dir/docs/adr/0001-first.md"
  git_test_config "$dir" add -A >/dev/null
  git_test_config "$dir" commit -qm base
}

# run_case <label> <expected-rc> [<path-to-add>...]
# Adds each path (committed), runs `--check`, asserts the exit code, and on an
# expected failure asserts that every added path is named in the output.
run_case() {
  local label="$1" expected="$2"
  shift 2
  local repo p out rc
  mk_repo repo || {
    fail "$label: fixture build failed"
    return
  }
  for p in "$@"; do
    mkdir -p "$repo/$(dirname "$p")"
    printf 'seed\n' >"$repo/$p"
  done
  if (($# > 0)); then
    git_test_config "$repo" add -A >/dev/null
    git_test_config "$repo" commit -qm case >/dev/null
  fi
  out="$(bash "$repo/scripts/check-docs-naming.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  if [[ $expected -eq 1 ]]; then
    for p in "$@"; do
      if ! grep -qF "$p" <<<"$out"; then
        fail "$label: offender $p not named in output: $out"
        return
      fi
    done
  fi
  ok "$label"
}

# 1. A clean tree passes.
run_case "clean tree passes" 0

# 2. An uppercase basename fails and is named.
run_case "docs/NEW-FILE.md fails" 1 docs/NEW-FILE.md

# 3. The conventional uppercase names are exempt anywhere under docs/.
run_case "docs/x/README.md passes" 0 docs/x/README.md docs/x/CHANGELOG.md docs/x/INDEX.md

# 4. The branch-only topic slice is exempt.
run_case "docs/topics/t/PLAN.md passes" 0 docs/topics/t/PLAN.md

# 5. Code files are judged by their language, not this rule.
run_case "docs/a/b_c.py passes" 0 docs/a/b_c.py docs/a/Run-Thing.ps1

# 6. Dotted stems and multi-part extensions are lower-kebab.
run_case "docs/a/v1.2.schema.json passes" 0 docs/a/v1.2.schema.json

# 7. Underscores and mixed case are not kebab.
run_case "docs/a/snake_case.md fails" 1 docs/a/snake_case.md

# 8. Two tracked paths that differ only by case fail even when each is a
#    conventional name on its own.
run_case "docs/Foo.md beside docs/foo.md fails" 1 docs/Foo.md docs/foo.md

# 9. Discover mode (no flag) lists offenders and still exits 1 on any.
repo=""
mk_repo repo
printf 'seed\n' >"$repo/docs/Bad-Name.md"
git_test_config "$repo" add -A >/dev/null
git_test_config "$repo" commit -qm case >/dev/null
out="$(bash "$repo/scripts/check-docs-naming.sh" 2>&1)"
rc=$?
if [[ $rc -eq 1 ]] && grep -qF 'docs/Bad-Name.md' <<<"$out"; then
  ok "discover mode names the offender and exits 1"
else
  fail "discover mode should name docs/Bad-Name.md and exit 1 (rc=$rc): $out"
fi

# 10. Unknown mode is a usage error, not a silent pass.
bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
