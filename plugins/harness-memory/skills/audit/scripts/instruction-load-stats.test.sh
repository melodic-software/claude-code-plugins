#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/instruction-load-stats.sh"

# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 in: $2" ;;
  esac
}

mkdir -p "$TEST_TMPDIR/conf"
export CLAUDE_CONFIG_DIR="$TEST_TMPDIR/conf"


rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_eq "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"
rc=0
bash "$SCRIPT" --bogus >/dev/null 2>&1 || rc=$?
assert_eq "a bad mode exits 2" 2 "$rc"


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


PLAIN="$TEST_TMPDIR/plain"
make_repo "$PLAIN"
printf '# Plain\n\nline a\nline b\n' >"$PLAIN/CLAUDE.md"
OUT=$(cd "$PLAIN" && bash "$SCRIPT" --lines)
assert_eq "--lines on an import-free file is its own non-blank count" "3" "$OUT"


EMPTY="$TEST_TMPDIR/empty"
make_repo "$EMPTY"
OUT=$(cd "$EMPTY" && bash "$SCRIPT" --lines)
assert_eq "--lines with no root file is 0" "0" "$OUT"
OUT=$(cd "$EMPTY" && bash "$SCRIPT" --tokens)
assert_eq "--tokens with nothing loaded is 0" "0" "$OUT"


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
OUT=$(cd "$CM" && bash "$SCRIPT" --lines)
assert_eq "--lines strips the block comment and keeps fenced content (7 + 1)" "8" "$OUT"


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


EXT="$TEST_TMPDIR/ext"
make_repo "$EXT"
printf 'outside\nouter line\n' >"$TEST_TMPDIR/outside.md"
printf '# Root\n@../outside.md\n' >"$EXT/CLAUDE.md"
OUT=$(cd "$EXT" && bash "$SCRIPT" --breakdown)
assert_contains "an external import is listed as external" "$OUT" "external	0	0	"
OUT=$(cd "$EXT" && bash "$SCRIPT" --lines)
assert_eq "--lines does not expand an external import" "2" "$OUT"


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
OUT=$(cd "$SET" && bash "$SCRIPT" --tokens)
assert_eq "--tokens is bytes/4 over the expanded set" "25" "$OUT"


USR="$TEST_TMPDIR/usr"
make_repo "$USR"
printf '# Project\n' >"$USR/CLAUDE.md"
UCFG="$TEST_TMPDIR/cfg"
mkdir -p "$UCFG/rules/deep" "$UCFG/notes"
UCFG=$(cd "$UCFG" && pwd -P)
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
OUT=$(cd "$USR" && CLAUDE_CONFIG_DIR="$UCFG" bash "$SCRIPT" --tokens)
assert_eq "--tokens covers both scopes" "13" "$OUT"
mkdir -p "$TEST_TMPDIR/home2/.claude"
printf '# Home user\n' >"$TEST_TMPDIR/home2/.claude/CLAUDE.md"
OUT=$(cd "$USR" && HOME="$TEST_TMPDIR/home2" CLAUDE_CONFIG_DIR='' bash "$SCRIPT" --tokens)
assert_eq "--tokens falls back to HOME/.claude (10 + 12 bytes)" "5" "$OUT"
OUT=$(cd "$USR" && CLAUDE_CONFIG_DIR="$UCFG" bash "$SCRIPT" --lines)
assert_eq "--lines is unaffected by the user layer" "1" "$OUT"


CRLF="$TEST_TMPDIR/crlf"
make_repo "$CRLF"
printf '# Root\r\nline\r\n' >"$CRLF/CLAUDE.md"
OUT=$(cd "$CRLF" && bash "$SCRIPT" --bytes)
assert_eq "--bytes measures LF-normalized content" "12" "$OUT"


AG="$TEST_TMPDIR/agents"
make_repo "$AG"
printf '# project instructions\n\nreal content\n' >"$AG/AGENTS.md"
OUT=$(cd "$AG" && bash "$SCRIPT" --breakdown)
assert_contains "a natively read AGENTS.md is an always-loaded root" "$OUT" "project	root	2	37	AGENTS.md"
OUT=$(cd "$AG" && bash "$SCRIPT" --tokens)
assert_eq "--tokens counts the AGENTS.md bytes (37/4)" "9" "$OUT"
OUT=$(cd "$AG" && bash "$SCRIPT" --lines)
assert_eq "--lines defaults to the AGENTS.md when it is what loads" "2" "$OUT"

printf '# project instructions\n@docs/more.md\n' >"$AG/AGENTS.md"
mkdir -p "$AG/docs"
printf 'more\n' >"$AG/docs/more.md"
OUT=$(cd "$AG" && bash "$SCRIPT" --breakdown)
assert_contains "an AGENTS.md import loads too" "$OUT" "import	1	5	docs/more.md"


SHIM="$TEST_TMPDIR/shim"
make_repo "$SHIM"
printf '@AGENTS.md\n' >"$SHIM/CLAUDE.md"
printf '# project instructions\n\nreal content\n' >"$SHIM/AGENTS.md"
OUT=$(cd "$SHIM" && bash "$SCRIPT" --breakdown)
assert_contains "the shim's AGENTS.md is the CLAUDE.md's import" "$OUT" "project	import	2	37	AGENTS.md"
assert_eq "the shimmed AGENTS.md is never also a root" "0" "$(printf '%s\n' "$OUT" | grep -c '	root	.*AGENTS.md')"
OUT=$(cd "$SHIM" && bash "$SCRIPT" --tokens)
assert_eq "--tokens counts the shimmed pair once (11 + 37 bytes)" "12" "$OUT"

BLOCKED="$TEST_TMPDIR/blocked"
make_repo "$BLOCKED"
printf 'local pref\n' >"$BLOCKED/CLAUDE.local.md"
printf '# project instructions\n\nreal content\n' >"$BLOCKED/AGENTS.md"
OUT=$(cd "$BLOCKED" && bash "$SCRIPT" --breakdown)
assert_not_contains "a displaced AGENTS.md is not in the always-loaded set" "$OUT" "AGENTS.md"


DOTAG="$TEST_TMPDIR/dot-agents"
make_repo "$DOTAG"
mkdir -p "$DOTAG/.claude"
printf '# project instructions\n' >"$DOTAG/.claude/AGENTS.md"
OUT=$(cd "$DOTAG" && bash "$SCRIPT" --breakdown)
assert_contains "a lone .claude/AGENTS.md is an always-loaded root" "$OUT" "project	root	1	23	.claude/AGENTS.md"
OUT=$(cd "$DOTAG" && bash "$SCRIPT" --lines)
assert_eq "--lines falls back to .claude/AGENTS.md" "1" "$OUT"

printf '# root instructions\n' >"$DOTAG/AGENTS.md"
OUT=$(cd "$DOTAG" && bash "$SCRIPT" --breakdown)
assert_contains "both AGENTS.md names are counted: root" "$OUT" "project	root	1	20	AGENTS.md"
assert_contains "both AGENTS.md names are counted: .claude" "$OUT" "project	root	1	23	.claude/AGENTS.md"
OUT=$(cd "$DOTAG" && bash "$SCRIPT" --tokens)
assert_eq "--tokens sums both AGENTS.md files (20 + 23)" "10" "$OUT"

source "$SCRIPT_DIR/lib/rule-scope.sh"
BIGFM="$TEST_TMPDIR/bigfm.md"
{
  printf -- '---\npaths:\n'
  for i in $(seq 1 20000); do printf '  - "dir%s/**/*.py"\n' "$i"; done
  printf -- '---\nbody\n'
} >"$BIGFM"
rc=0
rule_frontmatter_declares "$BIGFM" paths 2>/dev/null || rc=$?
assert_eq "a rule whose large frontmatter declares paths is path-scoped" "0" "$rc"
rc=0
rule_frontmatter_declares "$BIGFM" description 2>/dev/null || rc=$?
assert_eq "a key the large frontmatter lacks is not declared" "1" "$rc"

report_and_exit
