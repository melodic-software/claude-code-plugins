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

# expect <label> <mode> <content> <expected entries, newline-joined via $'\n'>
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

# A BARE `--comments` (the flag present, its mode value missing) must reach the
# same rc-2 answer, and must reach it AT ALL. The pre-#3363 arm consumed its
# value with `shift 2 || true`; as the last argument that shifted nothing and
# returned non-zero, `|| true` hid the failure, `$#` stayed at 1, and the option
# loop reprocessed `--comments` forever.
#
# The WATCHDOG is the load-bearing part of this assertion, not decoration:
# without a bound, a regression does not FAIL this suite, it HANGS it, and an
# unbounded stall in CI is worse than a red test. It is hand-rolled from
# `kill`/`wait` rather than written as `timeout 5` because GNU coreutils
# `timeout` is absent from a stock macOS userland, which
# scripts/check-shell-portability.sh names as the platform no runner here
# covers: on a developer's Mac that invocation would return 127 and fail a
# correct library. `sleep`, `kill` and `wait` are POSIX, so this bounds the
# probe everywhere. A killed probe reports 128+SIGKILL, never 2.
missing_value_rc=0
# shellcheck disable=SC2016  # $1/$2 are the inner `bash -c` positionals, deliberately unexpanded here
bash -c '
  . "$1"
  declare -a probe=()
  read_list::into probe "$2" --comments
' _ "$SELF_DIR/read-list.sh" "$f" 2>/dev/null &
probe_pid=$!
# SIGKILL on the watchdog SHELL, and no `wait` for it. SIGTERM would be
# deferred until its foreground `sleep` returned, costing the suite the full
# five seconds on the HAPPY path; SIGKILL cannot be deferred. Killing the shell
# rather than letting it fire against an already-reaped pid is also what keeps
# this free of a pid-reuse hazard: the orphaned `sleep` has nothing left to run
# the kill.
# The `>/dev/null 2>&1` is not cosmetic. Without it the orphaned `sleep`
# inherits this suite's stdout, and anything reading the suite through a pipe
# blocks for the full five seconds waiting for that last writer to close.
(
  sleep 5
  kill -9 "$probe_pid" 2>/dev/null
) >/dev/null 2>&1 &
watchdog_pid=$!
# `disown` drops the watchdog from the job table so bash does not announce its
# death. Measured on Git Bash (MSYS2), which prints
# `<script>: line N: <pid> Killed  ( sleep 5; ... )` to the suite's stderr
# without it, on the PASSING path; Linux bash stays quiet either way. The
# probe's own kill IS still announced, but only where this case already FAILs.
disown "$watchdog_pid" 2>/dev/null
wait "$probe_pid" || missing_value_rc=$?
kill -9 "$watchdog_pid" 2>/dev/null
if [[ "$missing_value_rc" -eq 2 ]]; then
  ok "a bare --comments (no mode value) returns 2 promptly"
elif [[ "$missing_value_rc" -ge 128 ]]; then
  fail "a bare --comments HUNG (watchdog killed it, rc=$missing_value_rc) instead of returning 2 (#3363)"
else
  fail "a bare --comments returned $missing_value_rc, want 2"
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

# --- read_list::into_text parses a string exactly as into parses a file ----
#
# The text reader exists for a list that has no path (a baseline read out of a
# git rev). Asserting it against the SAME inputs as the file reader is what
# proves the two share one parse rather than growing a second one.

text_expect() {
  local label="$1" mode="$2" content="$3" want="$4"
  local -a entries=()
  local got
  if ! read_list::into_text entries "$content" --comments "$mode"; then
    fail "$label: read_list::into_text returned non-zero"
    return
  fi
  got="$(printf '%s\n' ${entries[@]+"${entries[@]}"})"
  if [[ "$got" == "$want" ]]; then
    ok "$label"
  else
    fail "$label: got [$got] want [$want]"
  fi
}

text_expect "into_text inline: truncates at a non-leading #" inline $'keep me # drop\nb\n' $'keep me\nb'
text_expect "into_text leading: keeps a non-leading # as data" leading $'keep me # and this\n' $'keep me # and this'
text_expect "into_text: drops blanks and whole-line comments" inline $'# note\n\n  a  \n' $'a'
text_expect "into_text: keeps a final line with no trailing newline" inline $'a\nb' $'a\nb'
text_expect "into_text: an empty string is an empty list" inline '' ''

entries=()
if read_list::into_text entries $'a\n' 2>/dev/null; then
  fail "into_text accepted a missing --comments"
else
  ok "into_text requires --comments too"
fi

# --- the stale-entry guard -------------------------------------------------

read_list::reset_used
# shellcheck disable=SC2034  # passed to the library BY NAME; the nameref is the use
declare -a list=(alpha beta gamma)
read_list::mark_used beta
declare -a stale=()
read_list::stale_to stale list
if [[ "${stale[*]}" == "alpha gamma" ]]; then
  ok "stale_to returns the unmarked entries in list order"
else
  fail "stale_to returned [${stale[*]}], want [alpha gamma]"
fi

read_list::reset_used
read_list::mark_used alpha beta gamma
stale=()
read_list::stale_to stale list
if ((${#stale[@]} == 0)); then
  ok "a fully consumed list is not stale"
else
  fail "a fully consumed list reported [${stale[*]}] stale"
fi

# reset_used must actually forget, or a gate that walks two lists in one process
# would inherit the first list's marks and under-report the second.
read_list::reset_used
stale=()
read_list::stale_to stale list
if [[ "${stale[*]}" == "alpha beta gamma" ]]; then
  ok "reset_used forgets every mark"
else
  fail "after reset_used, stale_to returned [${stale[*]}]"
fi

# An empty list under `set -u` must not abort: the zero-entry list is the END
# state every shrink-only baseline is driving toward.
read_list::reset_used
# shellcheck disable=SC2034  # passed to the library BY NAME; the nameref is the use
declare -a empty_list=()
stale=(sentinel)
if read_list::stale_to stale empty_list && ((${#stale[@]} == 0)); then
  ok "an empty list yields no stale entries and does not abort"
else
  fail "an empty list did not yield an empty stale set"
fi

# A duplicated entry is reported once: the operator gets one line to delete.
read_list::reset_used
# shellcheck disable=SC2034  # passed to the library BY NAME; the nameref is the use
declare -a dupes=(same same other)
stale=()
read_list::stale_to stale dupes
if [[ "${stale[*]}" == "same other" ]]; then
  ok "a duplicated stale entry is reported once"
else
  fail "duplicate handling returned [${stale[*]}], want [same other]"
fi

# report_stale: one prefix, one line per stale entry, rc 1 only when stale.
read_list::reset_used
read_list::mark_used beta
report_out="$(read_list::report_stale list scripts/demo.txt 'no longer shadows anything' 2>&1)" && report_rc=0 || report_rc=$?
if [[ "$report_rc" == 1 ]]; then
  ok "report_stale returns 1 when the list holds a stale entry"
else
  fail "report_stale returned $report_rc, want 1"
fi
want_report=$'STALE BASELINE: scripts/demo.txt: \'alpha\' no longer shadows anything\nSTALE BASELINE: scripts/demo.txt: \'gamma\' no longer shadows anything'
if [[ "$report_out" == "$want_report" ]]; then
  ok "report_stale prints the one unified prefix per stale entry"
else
  fail "report_stale printed [$report_out]"
fi

read_list::reset_used
read_list::mark_used alpha beta gamma
if read_list::report_stale list scripts/demo.txt 'unused' >/dev/null 2>&1; then
  ok "report_stale returns 0 when nothing is stale"
else
  fail "report_stale returned non-zero for a fully consumed list"
fi

# stale_line is public so a gate whose entries go stale for different reasons
# still spells the prefix once.
line_out="$(read_list::stale_line scripts/demo.txt entry 'gained a CHANGELOG.md' 2>&1)"
if [[ "$line_out" == "STALE BASELINE: scripts/demo.txt: 'entry' gained a CHANGELOG.md" ]]; then
  ok "stale_line writes the unified diagnostic to stderr"
else
  fail "stale_line printed [$line_out]"
fi

read_list::reset_used

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
