#!/usr/bin/env bash
# Unit tests for scripts/lib/read-list.sh.
#
# The load-bearing assertions are the two-mode ones. `inline` and `leading`
# differ on exactly one input -- a line carrying a non-leading `#` -- and both
# behaviours are required by real files in this repo, so each mode is asserted
# against that input AND against the other mode's answer. A test that only
# checked one mode would pass just as happily against a library that had quietly
# collapsed the two (#3161).
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=read-list.sh
. "$SELF_DIR/read-list.sh"

# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"

# mk <content> -> path of a temp list file
mk() {
  local f
  f="$(mktemp)"
  printf '%s' "$1" >"$f"
  printf '%s' "$f"
}

# expect <label> <mode> <content> <expected entries, NUL-joined via $'\n'>
expect() {
  local label="$1" mode="$2" content="$3" want="$4"
  local f got
  f="$(mk "$content")"
  local -a entries=()
  if ! read_list::into entries "$f" --comments "$mode"; then
    fail "$label: read_list::into returned non-zero"
    rm -f "$f"
    return
  fi
  got="$(printf '%s\n' ${entries[@]+"${entries[@]}"})"
  if [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label: got [$got] want [$want]"
  fi
  rm -f "$f"
}

# --- shared basics ---------------------------------------------------------

for mode in inline leading; do
  expect "$mode: drops blank lines" "$mode" $'a\n\n\nb\n' $'a\nb'
  expect "$mode: drops a whole-line comment" "$mode" $'# note\na\n' $'a'
  expect "$mode: drops an INDENTED whole-line comment" "$mode" $'   # note\na\n' $'a'
  expect "$mode: trims surrounding whitespace" "$mode" $'   a   \n' $'a'
  expect "$mode: keeps a final line with no trailing newline" "$mode" $'a\nb' $'a\nb'
  expect "$mode: strips a trailing CR" "$mode" $'a\r\nb\r\n' $'a\nb'
done

# --- the divergence: a non-leading '#' -------------------------------------
#
# This is the whole reason the mode argument exists. `inline` truncates at the
# `#`; `leading` keeps it, because a token-list entry is an ERE and a regex may
# legitimately contain one. Asserting BOTH answers is what proves the two modes
# are genuinely distinct rather than one aliasing the other.

expect "inline: truncates at a non-leading #" inline $'keep me # drop this\n' $'keep me'
expect "leading: keeps a non-leading # as data" leading $'keep me # and this\n' $'keep me # and this'

expect "inline: a line that is only an inline comment vanishes" inline $'   # all comment\nreal\n' $'real'
expect "leading: an ERE containing # survives intact" leading $'^foo#bar$\n' $'^foo#bar$'

# The same input through both modes, asserted as a pair: a trailing `#` is data
# to one and a comment opener to the other. This is the #1513 shape for a token
# list — inline mode silently hands the scanner a SHORTER pattern than the file
# declares, so the gate enforces less than it reports and still exits 0.
expect "leading: a trailing-# entry survives intact" leading $'a#\nb\n' $'a#\nb'
expect "inline: the same entry is TRUNCATED to its pre-# text" inline $'a#\nb\n' $'a\nb'

# --- no escape syntax, by decision -----------------------------------------

expect "inline: backslash-# is NOT an escape (documented decision)" inline $'a\\#b\n' $'a\\'

# --- --comments is required, with no default -------------------------------

f="$(mk $'a\n')"
entries=()
if read_list::into entries "$f" 2>/dev/null; then
  fail "a missing --comments was accepted"
else
  ok "--comments is required (no silent default)"
fi
entries=()
if read_list::into entries "$f" --comments bogus 2>/dev/null; then
  fail "an unknown --comments mode was accepted"
else
  ok "an unknown --comments mode is rejected"
fi
entries=()
if read_list::into entries "$f" --bogus 2>/dev/null; then
  fail "an unknown option was accepted"
else
  ok "an unknown option is rejected"
fi
rm -f "$f"

# --- an unreadable file is loud, never an empty list -----------------------

entries=(sentinel)
if read_list::into entries /nonexistent/list.txt --comments inline 2>/dev/null; then
  fail "a missing file was reported as an empty list"
else
  ok "a missing file returns non-zero rather than an empty list"
fi

# --- the caller may name its out-array anything ----------------------------
#
# Same nameref-shadowing hazard #3144 measured in changed-files.sh: a local
# declared after the nameref binds and sharing the caller's name swallows the
# result. The names below are this function's own internals.

f="$(mk $'a\nb\n')"
for victim in file mode line out; do
  if (
    unset -v "$victim"
    declare -a "$victim"
    read_list::into "$victim" "$f" --comments inline >/dev/null 2>&1 || exit 1
    count=0
    eval "count=\${#${victim}[@]}"
    [[ "$count" == "2" ]]
  ); then
    ok "an out-array named '$victim' receives the entries"
  else
    fail "an out-array named '$victim' did not receive the entries (internal local shadows it)"
  fi
done
rm -f "$f"

# --- the shipped files still parse under the mode their consumer uses ------
#
# Liveness: these assert against the REAL data files, so a file that grows an
# entry its consumer's mode would mangle fails here rather than in production.

REPO="$(cd "$SELF_DIR/../.." && pwd)"
entries=()
if read_list::into entries "$REPO/scripts/shell-portability-tokens.txt" --comments leading &&
  ((${#entries[@]} > 0)); then
  ok "the shipped shell-portability token list yields ${#entries[@]} active patterns"
else
  fail "the shipped shell-portability token list yielded nothing"
fi
entries=()
if read_list::into entries "$REPO/scripts/docs-only-paths.txt" --comments inline &&
  ((${#entries[@]} > 0)); then
  ok "the shipped docs-only allowlist yields ${#entries[@]} active prefixes"
else
  fail "the shipped docs-only allowlist yielded nothing"
fi

test_harness::report
