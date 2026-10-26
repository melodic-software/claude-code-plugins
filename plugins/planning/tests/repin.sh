#!/usr/bin/env bash
# Re-pin one or more digest pins of interview-defenses.test.sh.
#
#   repin.sh [--test-file <path>] <pin-label>... <justification>
#
# The last argument is the justification; every argument before it is a pin label, so one
# call re-pins several pins under one reason. Run it after reading the diff of the guarded
# text and confirming the defense still holds; the commit carries the printed old -> new
# lines and the reason, and the PR review judges the change. It
#   1. finds, for each label, the one digest pin (pin_section, pin_frontmatter,
#      pin_case_digest, pin_case_set or pin_file) whose call line contains it (backslashes
#      ignored, so a label with backticks is typed plainly), resolving every label before
#      it writes anything,
#   2. runs the test once and reads each pin's `want X, got Y` failure,
#   3. rewrites only those pins' sha256 literals to their Y and inserts
#      `# <justification>` on the line above each call, beside the existing re-pin comments,
#   4. prints `<label>: <old> -> <new>` per pin, in the order named, for the commit message,
#   5. reruns the test once and prints PASS or FAIL.
# Every other line of the file stays byte-identical.
#
# Exit: 0 re-pinned and the test passes; 1 re-pinned but the test still fails;
# 2 usage or an unreadable test file; 3 a label matches no digest pin, or more than one,
# or names the same pin as an earlier label; 4 nothing changed: a named pin's digest
# already matches, or it fails for a reason a new digest does not fix (such as a section
# boundary that is no longer a unique heading line). On 2, 3 and 4 the file is unchanged.
set -uo pipefail

self="$(basename "$0")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
test_file="$here/interview-defenses.test.sh"

usage() {
  echo "usage: $self [--test-file <path>] <pin-label>... <justification>" >&2
  exit 2
}

if [[ "${1:-}" == "--test-file" ]]; then
  [[ $# -ge 2 ]] || usage
  test_file="$2"
  shift 2
fi
[[ $# -ge 2 ]] || usage
labels=("${@:1:$#-1}")
justification="${!#}"
for label in "${labels[@]}"; do
  [[ -n "$label" ]] || usage
done
if [[ -z "${justification//[[:space:]]/}" || "$justification" == *$'\n'* ]]; then
  echo "$self: the justification must be one non-empty line." >&2
  exit 2
fi
[[ -f "$test_file" ]] || {
  echo "$self: no test file at $test_file" >&2
  exit 2
}

# Locate a pin: "<call line>\t<sha line>" for every digest-pin call whose first line
# holds the label. The sha literal is the call's last argument, alone on its own line.
# The label rides in the environment, not -v: awk would process backslash escapes in a -v value.
find_pins() {
  REPIN_LABEL="$1" awk '
    # A quoted 64-hex literal is 66 characters; no {64} interval, which mawk may lack.
    function sha_len(s) { gsub(/[[:space:]]/, "", s); return length(s) }
    BEGIN { want = ENVIRON["REPIN_LABEL"] }
    /^pin_(section|frontmatter|case_digest|case_set|file) / {
      call = NR
      line = $0
      gsub(/\\/, "", line)
      hit = (index(line, want) > 0)
      next
    }
    call && /^[[:space:]]*"[0-9a-f]+"[[:space:]]*$/ && sha_len($0) == 66 {
      if (hit) print call "\t" NR
      call = 0
      next
    }
    call && /^[^[:space:]]/ { call = 0 }
  ' "$test_file"
}

# Resolve every label before any write, reporting each one that does not name exactly one
# new pin.
call_lines=()
sha_lines=()
refused=0
for label in "${labels[@]}"; do
  matches="$(find_pins "$label")"
  count=0
  [[ -n "$matches" ]] && count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  if [[ "$count" -ne 1 ]]; then
    echo "$self: \"$label\" matches $count digest pins in ${test_file}; name exactly one." >&2
    refused=1
    continue
  fi
  call_line="${matches%%$'\t'*}"
  for seen in ${call_lines[@]+"${call_lines[@]}"}; do
    if [[ "$seen" == "$call_line" ]]; then
      echo "$self: \"$label\" names the same digest pin as an earlier label; name each pin once." >&2
      refused=1
      continue 2
    fi
  done
  call_lines+=("$call_line")
  sha_lines+=("${matches##*$'\t'}")
done
[[ $refused -eq 0 ]] || exit 3

run_test() { bash "$test_file" 2>&1; }

out="$(run_test)"
olds=()
news=()
pin_labels=()
unchanged=0
for i in "${!call_lines[@]}"; do
  old="$(sed -n "${sha_lines[$i]}p" "$test_file" | tr -d ' \t"')"
  # The label is the call's first argument, backslashes dropped; it ends at the line's last quote.
  pin_label="$(sed -n "${call_lines[$i]}p" "$test_file" | tr -d "\\\\" | sed 's/^pin_[a-z_]* "\(.*\)"[[:space:]]*$/\1/')"
  # Read the failure line that names this pin's label (backslashes dropped on both sides), so
  # pins sharing a stale literal each get their own digest. When none names it, fall back to the
  # line with the old digest only if it is the one such line, so no pin takes another's digest.
  new="$(printf '%s\n' "$out" | tr -d '\r' | REPIN_LABEL="$pin_label" awk -v old="$old" '
    { line = $0; gsub(/\\/, "", line) }
    index(line, "(want " old ", got ") && index(line, ENVIRON["REPIN_LABEL"]) { print; exit }
  ' | sed -n "s/.*(want $old, got \([0-9a-f]\{64\}\)).*/\1/p")"
  if [[ -z "$new" ]]; then
    new="$(printf '%s\n' "$out" | tr -d '\r' | sed -n "s/.*(want $old, got \([0-9a-f]\{64\}\)).*/\1/p")"
    [[ "$new" == *$'\n'* ]] && new=""
  fi
  if [[ -z "$new" ]]; then
    echo "$self: nothing to change for ${pin_label}: the digest already matches, or the pin fails for a reason a new digest does not fix." >&2
    unchanged=1
  fi
  olds+=("$old")
  news+=("$new")
  pin_labels+=("$pin_label")
done
[[ $unchanged -eq 0 ]] || exit 4

tmp="$(mktemp "${TMPDIR:-/tmp}/repin.XXXXXX")" || exit 2
trap 'rm -f "$tmp"' EXIT
REPIN_NOTE="$justification" awk -v calls="${call_lines[*]}" -v shas="${sha_lines[*]}" -v news="${news[*]}" '
  BEGIN {
    note = ENVIRON["REPIN_NOTE"]
    n = split(calls, c, " ")
    split(shas, s, " ")
    split(news, d, " ")
    for (i = 1; i <= n; i++) { is_call[c[i]] = 1; new_at[s[i]] = d[i] }
  }
  NR in is_call { print "# " note }
  NR in new_at { sub(/[0-9a-f]+/, new_at[NR]) }
  { print }
' "$test_file" >"$tmp" || exit 2
# Write through the existing file so its mode and ownership stay.
cat "$tmp" >"$test_file" || exit 2

for i in "${!pin_labels[@]}"; do
  echo "${pin_labels[$i]}: ${olds[$i]} -> ${news[$i]}"
done
if run_test >/dev/null; then
  echo "PASS"
  exit 0
fi
echo "FAIL: ${test_file##*/} still fails after the re-pin; run it for the failing pins." >&2
exit 1
