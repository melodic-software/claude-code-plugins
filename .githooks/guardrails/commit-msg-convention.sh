#!/usr/bin/env bash
# guardrails commit-msg-convention sha256:2c8e3cb3fe60ec94871ad2fbc478bfc9a6e29f76e1ef484de7e8f9eb9385b7d3
# guardrails-commit-msg-convention v2
# guardrails commit-msg check: the commit subject matches the team convention.
#
#   commit-msg-convention.sh <message-file>   git runs it as commit-msg
#
# The tool-agnostic layer of commit-convention enforcement: the Claude Code
# guard sees only tool calls, while this git hook checks every commit in the
# repository, from an editor, `git commit -F <file>`, an IDE or another agent.
# It reads the team-tracked pattern (`subject_pattern` in
# .claude/source-control.md) through the same resolver the guard uses,
# installed beside this script as an entry asset.
#
# Sentinel: the "guardrails-commit-msg-convention" marker on line 1 or 3 marks
# this hook as derived FROM the tracked config, so convention-inference tooling
# must not count it as an independent signal.
#
# No tracked pattern: no enforcement, exit 0, silent. A pattern that is not POSIX
# ERE, an unreadable config or a resolver that cannot run also exits 0, but
# prints a notice with the resolver's diagnostic to stderr (this hook has no
# model channel): exit 1 with empty stderr is "no pattern", anything else a failure.
# Fixup, squash and amend subjects pass, as rebase --autosquash consumes them.
# A violation prints how to fix the subject and exits 1; this hook never
# suggests skipping it.
set -uo pipefail

msg_file="${1:-}"
[[ -n "$msg_file" && -f "$msg_file" ]] || exit 0

here="${BASH_SOURCE[0]%/*}"
[[ "$here" == "${BASH_SOURCE[0]}" ]] && here=.
resolver="$here/resolve-convention-pattern.sh"
[[ -f "$resolver" ]] || resolver="$here/../hooks/resolve-convention-pattern.sh"
# Resolver gone: no enforcement, never a blind block.
[[ -f "$resolver" ]] || exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
errf="$(mktemp 2>/dev/null)" || errf=/dev/null
subject_ere="$(bash "$resolver" "$repo_root" subject_pattern 2>"$errf")"
rc=$?
if ((rc != 0)); then
  err=""
  IFS= read -r -d '' err <"$errf" || true
  err="${err//[$'\r\n\t']/ }"
  err="${err#"${err%%[![:space:]]*}"}"
  err="${err%"${err##*[![:space:]]}"}"
  [[ "$errf" == /dev/null ]] || rm -f "$errf"
  # Exit 1 with empty stderr is "no convention tracked": quiet. Any other
  # failure means this check did not run; it still lets the commit through.
  if [[ -n "$err" || $rc -ne 1 ]]; then
    [[ -n "$err" ]] || err="exit status $rc, no message"
    echo "guardrails: the commit-msg convention check did not run, so this subject was not checked. The convention resolver reported \"${err:0:300}\"." >&2
  fi
  exit 0
fi
[[ "$errf" == /dev/null ]] || rm -f "$errf"
[[ -n "$subject_ere" ]] || exit 0

# The subject is the first non-empty line git keeps. Git drops comment lines
# only under the strip cleanup: commit.cleanup=strip, or the default when an
# editor ran. Git sets GIT_EDITOR=: for this hook when none did (-m, -F), so a
# `-m "#123 fix"` subject is kept and checked. A --cleanup flag cannot be seen
# here. The comment character follows core.commentChar; `auto` cannot be known
# here.
comment_char="$(git config --get core.commentChar 2>/dev/null || true)"
[[ -n "$comment_char" && "$comment_char" != auto ]] || comment_char="#"
case "$(git config --get commit.cleanup 2>/dev/null || true)" in
strip) strip=1 ;;
verbatim | whitespace | scissors) strip=0 ;;
*) if [[ "${GIT_EDITOR:-}" == ":" ]]; then strip=0; else strip=1; fi ;;
esac

subject=""
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  [[ -n "$line" ]] || continue
  ((strip)) && [[ "${line:0:1}" == "$comment_char" ]] && continue
  subject="$line"
  break
done <"$msg_file"

# An empty message: git aborts the commit itself.
[[ -n "$subject" ]] || exit 0

case "$subject" in
"fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
*) ;;
esac

grep -Eq -- "$subject_ere" <<<"$subject" && exit 0
{
  echo "guardrails: the commit subject does not match the team convention."
  echo "  subject: $subject"
  echo "  pattern: $subject_ere   (subject_pattern in .claude/source-control.md)"
  echo "Rewrite the subject to match the pattern and commit again. If the pattern"
  echo "itself is wrong, change it in .claude/source-control.md through a pull request."
} >&2
exit 1
