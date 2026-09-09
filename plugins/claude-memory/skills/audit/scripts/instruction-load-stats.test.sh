#!/usr/bin/env bash
# Regression tests for instruction-load-stats.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/instruction-load-stats.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# The whole-set modes add the user-scope layer, so the host's real config dir
# must never leak into these expectations: HOME is pinned to an empty fixture
# home and CLAUDE_CONFIG_DIR is cleared. The user-scope case below sets its own.
mkdir -p "$TEST_TMPDIR/home"
export HOME="$TEST_TMPDIR/home"
unset CLAUDE_CONFIG_DIR

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 in: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}

# Fixture git repos must never inherit an outer hook chain's exported git env.
make_repo() {
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE GIT_COMMON_DIR GIT_CONFIG
  mkdir -p "$1"
  (cd "$1" && git init -q && git config user.email "test@example.com" && git config user.name "test" && git commit -q --allow-empty -m init)
}

# --- Case 1: --help and a bad mode ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
rc=0
bash "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "a bad mode exits 2" 2 "$rc"

# --- The loophole this script closes: a 1-line CLAUDE.md importing a big AGENTS.md ---

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
printf '@AGENTS.md\n' >"$REPO/CLAUDE.md"
{
  printf '# Project\n\n'
  for i in $(seq 1 201); do printf 'line %s\n' "$i"; done
} >"$REPO/AGENTS.md"
(cd "$REPO" && git add -A && git commit -q -m "fixture")

OUT=$(cd "$REPO" && bash "$SCRIPT" --lines)
assert_eq "--lines counts the root plus its import (1 + 202 non-blank)" "203" "$OUT"

# --- Case: a CLAUDE.md with no imports reports only itself ---

PLAIN="$TEST_TMPDIR/plain"
make_repo "$PLAIN"
printf '# Plain\n\nline a\nline b\n' >"$PLAIN/CLAUDE.md"
OUT=$(cd "$PLAIN" && bash "$SCRIPT" --lines)
assert_eq "--lines on an import-free file is its own non-blank count" "3" "$OUT"

# --- Case: no CLAUDE.md at all reports 0 ---

EMPTY="$TEST_TMPDIR/empty"
make_repo "$EMPTY"
OUT=$(cd "$EMPTY" && bash "$SCRIPT" --lines)
assert_eq "--lines with no root file is 0" "0" "$OUT"
OUT=$(cd "$EMPTY" && bash "$SCRIPT" --tokens)
assert_eq "--tokens with nothing loaded is 0" "0" "$OUT"

# --- Case: comments are stripped outside fences, kept inside them; code spans and fences are not imports ---

CM="$TEST_TMPDIR/comments"
make_repo "$CM"
mkdir -p "$CM/docs"
cat >"$CM/CLAUDE.md" <<'EOF'
# Title
<!-- a maintainer note
spanning two lines -->
Mention `@docs/span.md` only.
```text
@docs/fenced.md
<!-- kept: inside a fence -->
```
See @docs/real.md.
EOF
printf 'real content\n' >"$CM/docs/real.md"
printf 'never\n' >"$CM/docs/span.md"
printf 'never\n' >"$CM/docs/fenced.md"
OUT=$(cd "$CM" && bash "$SCRIPT" --breakdown)
assert_contains "a bare @path outside code is imported" "$OUT" "docs/real.md"
assert_not_contains "a code-span @path is not imported" "$OUT" "docs/span.md"
assert_not_contains "a fenced @path is not imported" "$OUT" "docs/fenced.md"
# Root: "# Title", "Mention ... only.", 3 fence lines, "See @docs/real.md." = 7 non-blank; comment stripped.
OUT=$(cd "$CM" && bash "$SCRIPT" --lines)
assert_eq "--lines strips the block comment and keeps fenced content (7 + 1)" "8" "$OUT"

# --- Case: depth cap, cycle, missing, and diamond ---

DEEP="$TEST_TMPDIR/deep"
make_repo "$DEEP"
printf '@a.md\n' >"$DEEP/CLAUDE.md"
printf 'a\n@b.md\n' >"$DEEP/a.md"
printf 'b\n@c.md\n' >"$DEEP/b.md"
printf 'c\n@d.md\n' >"$DEEP/c.md"
printf 'd\n@e.md\n' >"$DEEP/d.md"
printf 'e\n@CLAUDE.md\n' >"$DEEP/e.md"
OUT=$(cd "$DEEP" && bash "$SCRIPT" --breakdown)
assert_contains "the fourth hop loads" "$OUT" "import	2	8	d.md"
assert_contains "the fifth hop is reported as past the depth cap" "$OUT" "depth	0	0	e.md"
OUT=$(cd "$DEEP" && bash "$SCRIPT" --lines)
assert_eq "--lines stops at four hops (root + a..d = 1 + 2*4)" "9" "$OUT"

CYC="$TEST_TMPDIR/cycle"
make_repo "$CYC"
printf '@x.md\n@y.md\n' >"$CYC/CLAUDE.md"
printf 'x\n@shared.md\n@CLAUDE.md\n' >"$CYC/x.md"
printf 'y\n@shared.md\n@gone.md\n' >"$CYC/y.md"
printf 'shared\n' >"$CYC/shared.md"
OUT=$(cd "$CYC" && bash "$SCRIPT" --breakdown)
assert_contains "a back-edge is reported as seen" "$OUT" "seen	0	0	CLAUDE.md"
assert_contains "a missing import is reported" "$OUT" "missing	0	0	gone.md"
assert_eq "a diamond loads the shared file once" "1" "$(printf '%s\n' "$OUT" | grep -c '	import	.*shared.md')"
assert_contains "a diamond's second edge is reported as seen" "$OUT" "seen	0	0	shared.md"
OUT=$(cd "$CYC" && bash "$SCRIPT" --lines)
assert_eq "--lines: root(2) + x(3) + y(3) + shared(1), shared once" "9" "$OUT"

# --- Case: an import outside the repository is listed, not expanded ---

EXT="$TEST_TMPDIR/ext"
make_repo "$EXT"
printf 'outside\nouter line\n' >"$TEST_TMPDIR/outside.md"
printf '# Root\n@../outside.md\n' >"$EXT/CLAUDE.md"
OUT=$(cd "$EXT" && bash "$SCRIPT" --breakdown)
assert_contains "an external import is listed as external" "$OUT" "external	0	0	"
OUT=$(cd "$EXT" && bash "$SCRIPT" --lines)
assert_eq "--lines does not expand an external import" "2" "$OUT"

# --- Case: the whole set adds unscoped rules and their imports, skips path-scoped rules ---

SET="$TEST_TMPDIR/set"
make_repo "$SET"
mkdir -p "$SET/.claude/rules/sub" "$SET/docs"
printf '# Root\n' >"$SET/CLAUDE.md"
printf 'local pref\n' >"$SET/CLAUDE.local.md"
printf '# Always\n@../../docs/shared.md\n' >"$SET/.claude/rules/always.md"
printf -- '---\npaths:\n  - "**/*.py"\n---\n# Scoped\nscoped body\n' >"$SET/.claude/rules/scoped.md"
printf -- '---\ndescription: nested\n---\nnested rule\n' >"$SET/.claude/rules/sub/nested.md"
printf 'shared doc\n' >"$SET/docs/shared.md"
OUT=$(cd "$SET" && bash "$SCRIPT" --breakdown)
assert_contains "CLAUDE.local.md is a root" "$OUT" "root	1	11	CLAUDE.local.md"
assert_contains "an unscoped rule is a root" "$OUT" ".claude/rules/always.md"
assert_contains "a nested unscoped rule is a root" "$OUT" ".claude/rules/sub/nested.md"
assert_contains "an unscoped rule's import loads" "$OUT" "import	1	11	docs/shared.md"
assert_not_contains "a path-scoped rule is not in the always-loaded set" "$OUT" "scoped.md"
assert_contains "TOTAL row carries the estimate label" "$OUT" "tokens (bytes/4, estimate)"
# Bytes: "# Root\n"=7, local=11, always.md ("# Always\n@../../docs/shared.md\n")=31,
# nested.md whole file (frontmatter counts)=40, shared=11 => 100 bytes => 25 tokens.
OUT=$(cd "$SET" && bash "$SCRIPT" --tokens)
assert_eq "--tokens is bytes/4 over the expanded set" "25" "$OUT"

# --- Case: the user-scope layer is part of the always-loaded set ---
# ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md and its unscoped rules load in
# every session of every project, so the whole-set modes count them; their
# imports expand within the config dir; a path-scoped user rule stays out.

USR="$TEST_TMPDIR/usr"
make_repo "$USR"
printf '# Project\n' >"$USR/CLAUDE.md"
UCFG="$TEST_TMPDIR/cfg"
mkdir -p "$UCFG/rules/deep" "$UCFG/notes"
printf '# User\n@notes/prefs.md\n' >"$UCFG/CLAUDE.md"
printf 'prefs body\n' >"$UCFG/notes/prefs.md"
printf 'user rule\n' >"$UCFG/rules/deep/always.md"
printf -- '---\npaths:\n  - "**/*.go"\n---\nscoped\n' >"$UCFG/rules/scoped.md"
OUT=$(cd "$USR" && CLAUDE_CONFIG_DIR="$UCFG" bash "$SCRIPT" --breakdown)
assert_contains "user CLAUDE.md is a user-scope root" "$OUT" "user	root	2	23	$UCFG/CLAUDE.md"
assert_contains "a user-scope import expands within the config dir" "$OUT" "user	import	1	11	$UCFG/notes/prefs.md"
assert_contains "an unscoped user rule is a user-scope root" "$OUT" "user	root	1	10	$UCFG/rules/deep/always.md"
assert_not_contains "a path-scoped user rule is not in the set" "$OUT" "scoped.md"
assert_contains "project rows keep the project scope" "$OUT" "project	root	1	10	CLAUDE.md"
# Bytes: project 10 + user 23 + 11 + 10 = 54 => 13 tokens.
OUT=$(cd "$USR" && CLAUDE_CONFIG_DIR="$UCFG" bash "$SCRIPT" --tokens)
assert_eq "--tokens covers both scopes" "13" "$OUT"
# HOME/.claude is the fallback when CLAUDE_CONFIG_DIR is unset.
mkdir -p "$TEST_TMPDIR/home2/.claude"
printf '# Home user\n' >"$TEST_TMPDIR/home2/.claude/CLAUDE.md"
OUT=$(cd "$USR" && HOME="$TEST_TMPDIR/home2" bash "$SCRIPT" --tokens)
assert_eq "--tokens falls back to HOME/.claude (10 + 12 bytes)" "5" "$OUT"
# The single-file modes stay project-only: C1 is a per-file check.
OUT=$(cd "$USR" && CLAUDE_CONFIG_DIR="$UCFG" bash "$SCRIPT" --lines)
assert_eq "--lines is unaffected by the user layer" "1" "$OUT"

# --- Case: CRLF content counts the same as LF ---

CRLF="$TEST_TMPDIR/crlf"
make_repo "$CRLF"
printf '# Root\r\nline\r\n' >"$CRLF/CLAUDE.md"
OUT=$(cd "$CRLF" && bash "$SCRIPT" --bytes)
assert_eq "--bytes measures LF-normalized content" "12" "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
