#!/usr/bin/env bash
# Unit tests for check-plugin-imports.sh, against a throwaway git tree with two
# plugins, alpha and beta, per case.
#
#   bash scripts/check-plugin-imports.test.sh
#
# The cases hold shell, JS, Python and PowerShell source as literal data.
# shellcheck disable=SC2016
set -uo pipefail
unset CHECK_DATA_ROOT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-plugin-imports.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

f=""
RULE='breaks the boundary rule "a plugin'"'"'s code never loads a file from a sibling plugin"'

# tree <file> <content> [<file> <content>]...: a fresh fixture with beta's
# library and the given files, all tracked, in $f.
tree() {
  fixture_tree::build f --sut "$SCRIPT" --git --plugins --label plugin-imports || return 2
  mkdir -p "$f/plugins/beta/lib" "$f/docs"
  printf 'x\n' >"$f/plugins/beta/lib/x.sh"
  while (($#)); do
    mkdir -p "$(dirname "$f/$1")"
    printf '%s\n' "$2" >"$f/$1"
    shift 2
  done
  git_test_config "$f" add -A >/dev/null
}

# run_check: sets RC, OUT and ERR for the check run in $f.
run_check() {
  RC=0
  OUT="$(cd "$f" && bash scripts/check-plugin-imports.sh 2>"$f.err")" || RC=$?
  ERR="$(cat "$f.err")"
  rm -f "$f.err"
}

# expect_pass <name>: the check exits 0 with its statement on stdout.
expect_pass() {
  run_check
  if [[ $RC == 0 && $OUT == "No plugin loads a file from a sibling plugin"* && -z $ERR ]]; then
    ok "$1"
  else
    bad "$1" "rc=$RC out=$OUT err=$ERR"
  fi
}

# expect_crossing <name> <path:line> <target>: the check exits 1, naming the
# rule, the line and where it lands, on stderr only.
expect_crossing() {
  run_check
  if [[ $RC == 1 && -z $OUT && $ERR == *"$2: $RULE"*"resolves to $3 in the beta plugin"* ]]; then
    ok "$1"
  else
    bad "$1" "rc=$RC out=$OUT err=$ERR"
  fi
}

A=plugins/alpha/scripts

# --- each load form that lands in a sibling plugin fails ----------------------
tree "$A/a.sh" $'#!/usr/bin/env bash\nsource "$SCRIPT_DIR/../../beta/lib/x.sh"'
expect_crossing "a source after \$SCRIPT_DIR into a sibling fails" "$A/a.sh:2" plugins/beta/lib/x.sh

tree "$A/a.sh" $'. "${HERE}/../../beta/lib/x.sh"\nbash "$(dirname "$0")/../../beta/lib/x.sh"'
expect_crossing "a braced variable anchor fails" "$A/a.sh:1" plugins/beta/lib/x.sh
expect_crossing "a dirname-of-self anchor fails" "$A/a.sh:2" plugins/beta/lib/x.sh

tree "$A/a.sh" '. "${BASH_SOURCE%/*}/../../beta/lib/x.sh"'
expect_crossing "a BASH_SOURCE%/* anchor fails" "$A/a.sh:1" plugins/beta/lib/x.sh

tree "$A/a.sh" 'HELPER="$SCRIPT_DIR/../../../plugins/beta/lib/x.sh"'
expect_crossing "a climb to the repository root and back into plugins/beta fails" "$A/a.sh:1" plugins/beta/lib/x.sh

tree "$A/a.mjs" $'import { x } from "../../beta/lib/x.mjs";\nconst y = await import("../../beta/lib/y.mjs");\nconst z = require("../../beta/lib/z.cjs");'
expect_crossing "a JS from specifier fails" "$A/a.mjs:1" plugins/beta/lib/x.mjs
expect_crossing "a JS dynamic import fails" "$A/a.mjs:2" plugins/beta/lib/y.mjs
expect_crossing "a JS require fails" "$A/a.mjs:3" plugins/beta/lib/z.cjs

tree "$A/a.tsx" 'import { x } from "../../beta/lib/x.ts";'
expect_crossing "a TSX from specifier fails" "$A/a.tsx:1" plugins/beta/lib/x.ts

tree "$A/a.mjs" 'const lib = join(here, "..", "..", "beta", "lib", "x.mjs");'
expect_crossing "join arguments after an anchor fail" "$A/a.mjs:1" plugins/beta/lib/x.mjs

tree "$A/a.py" 'LIB = Path(__file__).resolve().parents[2] / "beta" / "lib"'
expect_crossing "a pathlib parents[n] from __file__ fails" "$A/a.py:1" plugins/beta/lib

tree "$A/a.py" $'LIB = HERE.parent.parent / "beta" / "lib"\nsys.path.insert(0, os.path.join(HERE, "../../beta/lib"))'
expect_crossing "a pathlib .parent chain from a directory variable fails" "$A/a.py:1" plugins/beta/lib
expect_crossing "os.path.join with a climbing literal fails" "$A/a.py:2" plugins/beta/lib

# portability-ok: the backslashes are PowerShell path separators in fixture text, not a regex
tree "$A/a.ps1" $'. "$PSScriptRoot\\..\\..\\beta\\lib\\x.ps1"\n$p = Join-Path $PSScriptRoot \'..\\..\\beta\\lib\\y.ps1\''
expect_crossing "a PowerShell dot-source with backslashes fails" "$A/a.ps1:1" plugins/beta/lib/x.ps1
expect_crossing "a PowerShell Join-Path fails" "$A/a.ps1:2" plugins/beta/lib/y.ps1

# --- shapes that are not crossings, each beside the same path as a load -------
# Every pair holds the same path twice: the case passes only when the data line
# is skipped and the load line is still caught.
pair() { # <name> <file> <data line> <load line>
  tree "$2" "$3"
  expect_pass "$1: alone it passes"
  tree "$2" "$3"$'\n'"$4"
  expect_crossing "$1: the same path as a load on line 2 fails" "$2:2" "$5"
}
pair "a shell comment" "$A/a.sh" '# source "$SCRIPT_DIR/../../beta/lib/x.sh"' 'source "$SCRIPT_DIR/../../beta/lib/x.sh"' plugins/beta/lib/x.sh
pair "a JS line comment" "$A/a.mjs" '// import { x } from "../../beta/lib/x.mjs";' 'import { x } from "../../beta/lib/x.mjs";' plugins/beta/lib/x.mjs
pair "a JS block-comment line" "$A/a.mjs" ' * reads $SCRIPT_DIR/../../beta/lib/x.mjs' 'const p = `${SCRIPT_DIR}/../../beta/lib/x.mjs`;' plugins/beta/lib/x.mjs
pair "a Python comment" "$A/a.py" '# LIB = Path(__file__).resolve().parents[2] / "beta" / "lib"' 'LIB = Path(__file__).resolve().parents[2] / "beta" / "lib"' plugins/beta/lib
pair "a path with no anchor, held as data" "$A/a.mjs" 'const path = "reference/../../beta/lib/x.mjs";' 'import { x } from "../../beta/lib/x.mjs";' plugins/beta/lib/x.mjs
pair "a glob held as data" "$A/a.py" 'PATHS = ("plugins/beta/lib/**", "../beta/lib/**")' 'LIB = os.path.join(HERE, "../../beta/lib")' plugins/beta/lib

tree "$A/run" $'#!/usr/bin/env bash\nsource "$SCRIPT_DIR/../../beta/lib/x.sh"' "$A/notes" 'source "$SCRIPT_DIR/../../beta/lib/x.sh"'
expect_crossing "an extensionless #! script is read" "$A/run:2" plugins/beta/lib/x.sh
if [[ $ERR != *"$A/notes"* ]]; then ok "an extensionless file with no #! is not read"; else bad "an extensionless file with no #! is not read" "$ERR"; fi

tree "$A/a.sh" $'source "$SCRIPT_DIR/../lib/x.sh"\ncat "$SCRIPT_DIR/../../../docs/x.md"\ncat "$SCRIPT_DIR/../../gamma/x.sh"'
expect_pass "a path inside the own plugin, outside plugins/, or into no plugin passes"

tree "$A/a.sh" 'source "$SCRIPT_DIR/../../beta/lib/x.sh"'
rm -f "$f/$A/a.sh"
git_test_config "$f" rm -q --cached "$A/a.sh" >/dev/null
printf 'source "$SCRIPT_DIR/../../beta/lib/x.sh"\n' >"$f/$A/untracked.sh"
expect_pass "an untracked file is not read"

# --- the exceptions file --------------------------------------------------------
crossing=$'#!/usr/bin/env bash\nsource "$SCRIPT_DIR/../../beta/lib/x.sh"'
tree "$A/a.sh" "$crossing" scripts/plugin-imports-exceptions.txt "# header
$A/a.sh beta 2026-11-16 agreement gate: both plugins carry the same literal"
expect_pass "a listed crossing passes"

tree "$A/a.sh" "$crossing" "$A/b.sh" "$crossing" scripts/plugin-imports-exceptions.txt "$A/a.sh beta 2026-11-16 agreement gate"
expect_crossing "a crossing in a file the list does not name still fails" "$A/b.sh:2" plugins/beta/lib/x.sh
if [[ $ERR != *"$A/a.sh:2"* ]]; then ok "the listed file is not reported"; else bad "the listed file is not reported" "$ERR"; fi

tree "$A/a.sh" 'true' scripts/plugin-imports-exceptions.txt "$A/a.sh beta 2026-11-16 agreement gate"
run_check
if [[ $RC == 1 && $ERR == *"STALE BASELINE: scripts/plugin-imports-exceptions.txt: '$A/a.sh beta 2026-11-16 agreement gate' no longer loads a file from that sibling plugin."* ]]; then
  ok "a listed file that no longer crosses fails as stale"
else
  bad "a listed file that no longer crosses fails as stale" "rc=$RC err=$ERR"
fi

tree "$A/a.sh" "$crossing" scripts/plugin-imports-exceptions.txt "$A/a.sh beta"
run_check
if [[ $RC == 1 && $ERR == *"MALFORMED: scripts/plugin-imports-exceptions.txt: '$A/a.sh beta'"* ]]; then
  ok "an entry missing its accepted day and reason fails as malformed"
else
  bad "an entry missing its accepted day and reason fails as malformed" "rc=$RC err=$ERR"
fi

# --- could not run ----------------------------------------------------------------
tree "$A/a.sh" 'true'
RC=0
OUT="$(cd "$f" && bash scripts/check-plugin-imports.sh --check 2>&1)" || RC=$?
if [[ $RC == 2 && $OUT == usage:* ]]; then
  ok "an argument is a usage error, exit 2"
else
  bad "an argument is a usage error, exit 2" "rc=$RC out=$OUT"
fi
plain="$(mktemp -d)"
RC=0
OUT="$(CHECK_DATA_ROOT="$plain" bash "$f/scripts/check-plugin-imports.sh" 2>&1)" || RC=$?
rm -rf "$plain"
if [[ $RC == 2 && $OUT == *"is not a git work tree"* ]]; then
  ok "a tree that is not a git work tree exits 2"
else
  bad "a tree that is not a git work tree exits 2" "rc=$RC out=$OUT"
fi

test_harness::report
