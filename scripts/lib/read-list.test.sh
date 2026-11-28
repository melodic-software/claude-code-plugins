#!/usr/bin/env bash
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=read-list.sh
. "$SELF_DIR/read-list.sh"

# shellcheck source=test-harness.sh
. "$SELF_DIR/test-harness.sh"

mk() {
  local f
  f="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  printf '%s' "$1" >"$f"
  printf '%s' "$f"
}

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

for mode in inline leading; do
  expect "$mode: drops blank lines" "$mode" $'a\n\n\nb\n' $'a\nb'
  expect "$mode: drops a whole-line comment" "$mode" $'# note\na\n' $'a'
  expect "$mode: drops an INDENTED whole-line comment" "$mode" $'   # note\na\n' $'a'
  expect "$mode: trims surrounding whitespace" "$mode" $'   a   \n' $'a'
  expect "$mode: keeps a final line with no trailing newline" "$mode" $'a\nb' $'a\nb'
  expect "$mode: strips a trailing CR" "$mode" $'a\r\nb\r\n' $'a\nb'
done

expect "inline: truncates at a non-leading #" inline $'keep me # drop this\n' $'keep me'
expect "leading: keeps a non-leading # as data" leading $'keep me # and this\n' $'keep me # and this'

expect "inline: a line that is only an inline comment vanishes" inline $'   # all comment\nreal\n' $'real'
expect "leading: an ERE containing # survives intact" leading $'^foo#bar$\n' $'^foo#bar$'

expect "leading: a trailing-# entry survives intact" leading $'a#\nb\n' $'a#\nb'
expect "inline: the same entry is TRUNCATED to its pre-# text" inline $'a#\nb\n' $'a\nb'

expect "inline: backslash-# is NOT an escape (documented decision)" inline $'a\\#b\n' $'a\\'

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

missing_value_rc=0
# shellcheck disable=SC2016  # $1/$2 are the inner `bash -c` positionals, deliberately unexpanded here
bash -c '
  . "$1"
  declare -a probe=()
  read_list::into probe "$2" --comments
' _ "$SELF_DIR/read-list.sh" "$f" 2>/dev/null &
probe_pid=$!
(
  sleep 5
  kill -9 "$probe_pid" 2>/dev/null
) >/dev/null 2>&1 &
watchdog_pid=$!
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

entries=(sentinel)
if read_list::into entries /nonexistent/list.txt --comments inline 2>/dev/null; then
  fail "a missing file was reported as an empty list"
else
  ok "a missing file returns non-zero rather than an empty list"
fi

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

read_list::reset_used
stale=()
read_list::stale_to stale list
if [[ "${stale[*]}" == "alpha beta gamma" ]]; then
  ok "reset_used forgets every mark"
else
  fail "after reset_used, stale_to returned [${stale[*]}]"
fi

read_list::reset_used
# shellcheck disable=SC2034  # passed to the library BY NAME; the nameref is the use
declare -a empty_list=()
stale=(sentinel)
if read_list::stale_to stale empty_list && ((${#stale[@]} == 0)); then
  ok "an empty list yields no stale entries and does not abort"
else
  fail "an empty list did not yield an empty stale set"
fi

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

line_out="$(read_list::stale_line scripts/demo.txt entry 'gained a CHANGELOG.md' 2>&1)"
if [[ "$line_out" == "STALE BASELINE: scripts/demo.txt: 'entry' gained a CHANGELOG.md" ]]; then
  ok "stale_line writes the unified diagnostic to stderr"
else
  fail "stale_line printed [$line_out]"
fi

read_list::reset_used

REPO="$(cd "$SELF_DIR/../.." && pwd)"
entries=()
if read_list::into entries "$REPO/scripts/shell-portability-tokens.txt" --comments leading &&
  ((${#entries[@]} > 0)); then
  ok "the shipped shell-portability token list yields ${#entries[@]} active patterns"
else
  fail "the shipped shell-portability token list yielded nothing"
fi
entries=()
if read_list::into entries "$REPO/scripts/affected-tests-no-suite.txt" --comments inline &&
  ((${#entries[@]} > 0)); then
  ok "the shipped no-suite list yields ${#entries[@]} active prefixes"
else
  fail "the shipped no-suite list yielded nothing"
fi

test_harness::report
