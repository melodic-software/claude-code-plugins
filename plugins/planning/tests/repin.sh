#!/usr/bin/env bash
# Attended re-pin for one digest pin of interview-defenses.test.sh.
#
#   repin.sh [--test-file <path>] <pin-label> <justification>
#
# A person runs this after reading the git diff of the guarded text and confirming
# the defense still holds. It refuses to write unless stdin and stdout are both
# terminals, and then writes only after the person answers y to the shown old and
# new digest and diff stat. There is no flag or variable to skip either check. It
#   1. finds the one digest pin (pin_section, pin_frontmatter, pin_case_digest,
#      pin_case_set or pin_file) whose call line contains <pin-label> (backslashes
#      ignored, so a label with backticks is typed plainly),
#   2. runs the test and reads that pin's `want X, got Y` failure,
#   3. checks for a terminal, shows the old and new digest and `git diff --stat`
#      of the plugin, and asks y/N (default N),
#   4. rewrites only that pin's sha256 literal to Y and inserts `# <justification>`
#      on the line above the call, beside the existing re-pin comments,
#   5. reruns the test and prints PASS or FAIL.
# Every other line of the file stays byte-identical.
#
# Exit: 0 re-pinned and the test passes; 1 re-pinned but the test still fails;
# 2 usage or an unreadable test file; 3 the label matches no digest pin, or more
# than one; 4 nothing changed: the digest already matches, or the pin fails for a
# reason a new digest does not fix (such as a section boundary that is no longer a
# unique heading line); 5 stdin or stdout is not a terminal; 6 the person declined.
set -uo pipefail

self="$(basename "$0")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
test_file="$here/interview-defenses.test.sh"

usage() {
  echo "usage: $self [--test-file <path>] <pin-label> <justification>" >&2
  exit 2
}

if [[ "${1:-}" == "--test-file" ]]; then
  [[ $# -ge 2 ]] || usage
  test_file="$2"
  shift 2
fi
[[ $# -eq 2 ]] || usage
label="$1"
justification="$2"
[[ -n "$label" ]] || usage
if [[ -z "${justification//[[:space:]]/}" || "$justification" == *$'\n'* ]]; then
  echo "$self: the justification must be one non-empty line." >&2
  exit 2
fi
[[ -f "$test_file" ]] || {
  echo "$self: no test file at $test_file" >&2
  exit 2
}

# Locate the pin: "<call line>\t<sha line>" for every digest-pin call whose first line
# holds the label. The sha literal is the call's last argument, alone on its own line.
# The label rides in the environment, not -v: awk would process backslash escapes in a -v value.
matches="$(REPIN_LABEL="$label" awk '
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
' "$test_file")"
count=0
[[ -n "$matches" ]] && count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
if [[ "$count" -ne 1 ]]; then
  echo "$self: \"$label\" matches $count digest pins in ${test_file}; name exactly one." >&2
  exit 3
fi
call_line="${matches%%$'\t'*}"
sha_line="${matches##*$'\t'}"
old="$(sed -n "${sha_line}p" "$test_file" | tr -d ' \t"')"

run_test() { bash "$test_file" 2>&1; }

out="$(run_test)"
new="$(printf '%s\n' "$out" | tr -d '\r' | sed -n "s/.*(want $old, got \([0-9a-f]\{64\}\)).*/\1/p" | head -1)"
if [[ -z "$new" ]]; then
  stripped="$(sed -n "${call_line}p" "$test_file" | tr -d "\\\\")"
  echo "$self: nothing to change for ${stripped}: the digest already matches, or the pin fails for a reason a new digest does not fix." >&2
  exit 4
fi

if ! [[ -t 0 && -t 1 ]]; then
  echo "$self: refusing to re-pin: stdin and stdout must both be a terminal. A person runs this in their own terminal after reading the diff; a Claude Code ! line has no terminal, and an unattended run reports the failing pin and stops." >&2
  exit 5
fi
echo "Pin: $(sed -n "${call_line}p" "$test_file" | tr -d "\\\\")"
echo "Old digest: $old"
echo "New digest: $new"
plugin_dir="$(cd "$(dirname "$test_file")/.." && pwd)"
echo "Changes under $plugin_dir since HEAD:"
# --no-pager: a pager would read the y/N answer from the terminal.
git --no-pager -C "$plugin_dir" diff --stat HEAD -- . 2>/dev/null || echo "(no git diff available)"
read -r -p "Write the new digest? [y/N] " answer || answer=""
if [[ "$answer" != [yY] && "$answer" != [yY][eE][sS] ]]; then
  echo "$self: not re-pinned." >&2
  exit 6
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/repin.XXXXXX")" || exit 2
trap 'rm -f "$tmp"' EXIT
REPIN_NOTE="$justification" awk -v call="$call_line" -v shaln="$sha_line" -v new="$new" '
  BEGIN { note = ENVIRON["REPIN_NOTE"] }
  NR == call { print "# " note }
  NR == shaln { sub(/[0-9a-f]+/, new) }
  { print }
' "$test_file" >"$tmp" || exit 2
# Write through the existing file so its mode and ownership stay.
cat "$tmp" >"$test_file" || exit 2

echo "$self: re-pinned line $sha_line: $old -> $new"
if run_test >/dev/null; then
  echo "PASS"
  exit 0
fi
echo "FAIL: ${test_file##*/} still fails after the re-pin; run it for the failing pins." >&2
exit 1
