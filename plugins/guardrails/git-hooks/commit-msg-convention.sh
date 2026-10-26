#!/bin/sh
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
# So do the subjects git writes itself: `Merge ...` from git merge and
# `Revert "..."` from git revert.
# A violation prints how to fix the subject and exits 1; this hook never
# suggests skipping it.
#
# POSIX sh, the resolver too, run with `sh`: it needs no bash beside git's sh,
# and on Windows a bash looked up by name can be System32's WSL launcher.
# shellcheck shell=sh
set -u

msg_file="${1:-}"
[ -n "$msg_file" ] || exit 0
[ -f "$msg_file" ] || exit 0

case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
resolver="$here/resolve-convention-pattern.sh"
[ -f "$resolver" ] || resolver="$here/../hooks/resolve-convention-pattern.sh"
# Resolver gone: no enforcement, never a blind block.
[ -f "$resolver" ] || exit 0

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
errf="$(mktemp 2>/dev/null)" || errf=/dev/null
subject_ere="$(sh "$resolver" "$repo_root" subject_pattern 2>"$errf")"
rc=$?
if [ "$rc" -ne 0 ]; then
  err="$(tr '\r\n\t' '   ' <"$errf")"
  err="${err#"${err%%[![:space:]]*}"}"
  err="${err%"${err##*[![:space:]]}"}"
  [ "$errf" = /dev/null ] || rm -f "$errf"
  # Exit 1 with empty stderr is "no convention tracked": quiet. Any other
  # failure means this check did not run; it still lets the commit through.
  if [ -n "$err" ] || [ "$rc" -ne 1 ]; then
    [ -n "$err" ] || err="exit status $rc, no message"
    printf 'guardrails: the commit-msg convention check did not run, so this subject was not checked. The convention resolver reported "%.300s".\n' "$err" >&2
  fi
  exit 0
fi
[ "$errf" = /dev/null ] || rm -f "$errf"
[ -n "$subject_ere" ] || exit 0

# The subject is the first non-empty line git keeps. Git drops comment lines
# only under the strip cleanup: commit.cleanup=strip, or the default when an
# editor ran. Git sets GIT_EDITOR=: for this hook when none did (-m, -F), so a
# `-m "#123 fix"` subject is kept and checked. A --cleanup flag cannot be seen
# here. The comment character follows core.commentChar; `auto` cannot be known
# here.
comment_char="$(git config --get core.commentChar 2>/dev/null || true)"
case "$comment_char" in
"" | auto) comment_char="#" ;;
*) ;;
esac
case "$(git config --get commit.cleanup 2>/dev/null || true)" in
strip) strip=1 ;;
verbatim | whitespace | scissors) strip=0 ;;
*) if [ "${GIT_EDITOR:-}" = ":" ]; then strip=0; else strip=1; fi ;;
esac

cr="$(printf '\r')"
subject=""
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%"$cr"}"
  [ -n "$line" ] || continue
  if [ "$strip" -eq 1 ]; then
    case "$line" in
    "$comment_char"*) continue ;;
    *) ;;
    esac
  fi
  subject="$line"
  break
done <"$msg_file"

# An empty message: git aborts the commit itself.
[ -n "$subject" ] || exit 0

case "$subject" in
"fixup! "* | "squash! "* | "amend! "* | "Merge "* | 'Revert "'*) exit 0 ;;
*) ;;
esac

# A heredoc, as POSIX sh has no here-string: a pipe into an early-exit grep can
# kill its writer.
grep -Eq -- "$subject_ere" <<EOF && exit 0
$subject
EOF
{
  echo "guardrails: the commit subject does not match the team convention."
  printf '  subject: %s\n' "$subject"
  printf '  pattern: %s   (subject_pattern in .claude/source-control.md)\n' "$subject_ere"
  echo "Rewrite the subject to match the pattern and commit again. If the pattern"
  echo "itself is wrong, change it in .claude/source-control.md through a pull request."
} >&2
exit 1
