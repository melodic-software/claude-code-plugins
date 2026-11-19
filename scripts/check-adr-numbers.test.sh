#!/usr/bin/env bash
# Black-box contract test for check-adr-numbers.sh.
#
# Self-contained and cwd-independent: builds a throwaway tree with a fixture
# docs/adr/ and baseline, runs the checker against it, and asserts on exit code
# and output. Mutates only its own mktemp dir. The SUT resolves the repository
# root relative to its own location, so the fixture tree carries a copy of it
# under scripts/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-adr-numbers.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# mk_tree <out-var>: a tree with unique ADRs, one baselined pair, and a
# baseline that lists exactly that pair.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label adr-numbers || return 1
  dir="${!1}"
  mkdir -p "$dir/docs/adr"
  printf 'seed\n' >"$dir/docs/adr/0001-first.md"
  printf 'seed\n' >"$dir/docs/adr/0002-second.md"
  printf 'seed\n' >"$dir/docs/adr/0003-old-a.md"
  printf 'seed\n' >"$dir/docs/adr/0003-old-b.md"
  printf 'seed\n' >"$dir/docs/adr/README.md"
  printf '# known pair\n0003-old-a.md\n0003-old-b.md  # inline comment\n' >"$dir/scripts/adr-numbers-baseline.txt"
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
# <setup> runs inside the fixture root; each <must-name> must appear in the
# output of a failing run.
run_case() { test_harness::check_case mk_tree check-adr-numbers.sh "$@"; }

run_case "clean tree with a baselined pair passes" 0 ":"

run_case "a fresh duplicate fails and names both files" 1 \
  "printf 'seed\n' >docs/adr/0002-second-again.md" \
  "0002: docs/adr/0002-second-again.md, docs/adr/0002-second.md"

run_case "a third record on a baselined number fails" 1 \
  "printf 'seed\n' >docs/adr/0003-old-c.md" \
  "0003: docs/adr/0003-old-a.md, docs/adr/0003-old-b.md, docs/adr/0003-old-c.md"

run_case "a baseline entry that no longer collides fails as stale" 1 \
  "rm docs/adr/0003-old-b.md" \
  "0003-old-a.md, whose number no longer collides" "0003-old-b.md, which does not exist"

run_case "a baseline entry naming a missing file fails as stale" 1 \
  "printf '0009-gone.md\n' >>scripts/adr-numbers-baseline.txt" \
  "docs/adr/0009-gone.md, which does not exist"

run_case "no docs/adr directory passes" 0 \
  "rm -r docs/adr && : >scripts/adr-numbers-baseline.txt"

run_case "a malformed baseline entry is an environment error" 2 \
  "printf 'not-an-adr\n' >>scripts/adr-numbers-baseline.txt" \
  "not-an-adr is not an ADR basename"

run_case "a missing baseline is an environment error" 2 \
  "rm scripts/adr-numbers-baseline.txt"

# Findings on stderr only; the clean statement on stdout only.
tree=""
if mk_tree tree; then
  printf 'seed\n' >"$tree/docs/adr/0001-first-again.md"
  test_harness::assert_discover_quiet "$tree/scripts/check-adr-numbers.sh"
else
  fail "discover mode: fixture build failed"
fi

test_harness::assert_unknown_mode "$SUT_SRC"

test_harness::report
