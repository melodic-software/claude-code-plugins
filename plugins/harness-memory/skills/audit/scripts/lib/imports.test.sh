#!/usr/bin/env bash
# Regression tests for how imports.sh reads an import path. Expected values come
# from https://code.claude.com/docs/en/memory#import-additional-files (read
# 2026-11-04): a backslash keeps a space in the path, a bare space ends the path,
# and a path wrapped in quotes is not imported.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../../scripts/test-helpers.sh"
# shellcheck source=imports.sh
source "$SCRIPT_DIR/imports.sh"

DIR="$(cd "$TEST_TMPDIR" && pwd)"
FILE="$DIR/CLAUDE.md"

imports_of() {
  printf '%s\n' "$1" >"$FILE"
  il_imports_of "$FILE"
}

# --- The page's worked example ---
assert_eq "an escaped space stays in the path" \
  "$DIR/Design Docs/api-conventions.md" \
  "$(imports_of '- API conventions @Design\ Docs/api-conventions.md')"
assert_eq "several escaped spaces all stay" \
  "$DIR/a b c.md" \
  "$(imports_of '@a\ b\ c.md')"

# --- A bare space ends the path, even on a line of its own ---
assert_eq "a bare space ends the path" \
  "$DIR/Design" \
  "$(imports_of '@Design Docs/api-conventions.md')"

# --- A quoted path is not imported, with or without the backslashes ---
assert_eq "a double-quoted path is not imported" "" "$(imports_of '@"Design Docs/a.md"')"
assert_eq "a double-quoted path with backslashes is not imported" "" "$(imports_of '@"Design\ Docs/a.md"')"
assert_eq "a single-quoted path is not imported" "" "$(imports_of "@'a.md'")"
assert_eq "a quoted path leaves the plain import on its line" \
  "$DIR/real.md" \
  "$(imports_of '@"a.md" and @real.md')"

# --- The forms the page's example block shows keep working ---
assert_eq "a plain import resolves against the file" "$DIR/README" "$(imports_of 'See @README for details')"
assert_eq "trailing punctuation is not part of the path" "$DIR/a.md" "$(imports_of 'See @a.md.')"

# --- The walk reaches a file behind an escaped space ---
mkdir -p "$DIR/Design Docs"
printf 'body\n' >"$DIR/Design Docs/a.md"
printf '%s\n' '@Design\ Docs/a.md' >"$FILE"
if il_reaches "$FILE" "$(il_realpath "$DIR/Design Docs/a.md")"; then
  pass "il_reaches follows an escaped-space import"
else
  fail "il_reaches follows an escaped-space import" "no path to Design Docs/a.md"
fi
assert_eq "il_walk lists the file as an import" \
  "import	$(il_realpath "$DIR/Design Docs/a.md")" \
  "$(il_walk "$FILE" | grep -v '^root')"

report_and_exit
