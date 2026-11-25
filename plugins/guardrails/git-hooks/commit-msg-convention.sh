#!/bin/sh
# shellcheck shell=sh
set -u

msg_file="${1:-}"
[ -f "$msg_file" ] || exit 0

case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
resolver="$here/resolve-convention-pattern.sh"
[ -f "$resolver" ] || resolver="$here/../hooks/resolve-convention-pattern.sh"
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
  if [ -n "$err" ] || [ "$rc" -ne 1 ]; then
    [ -n "$err" ] || err="exit status $rc, no message"
    printf 'guardrails: the commit-msg convention check did not run, so this subject was not checked. The convention resolver reported "%.300s".\n' "$err" >&2
  fi
  exit 0
fi
[ "$errf" = /dev/null ] || rm -f "$errf"
[ -n "$subject_ere" ] || exit 0

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

[ -n "$subject" ] || exit 0

case "$subject" in
"fixup! "* | "squash! "* | "amend! "* | "Merge "* | 'Revert "'*) exit 0 ;;
*) ;;
esac

grep -Eq -- "$subject_ere" <<EOF && exit 0
$subject
EOF
layer="$(sh "$resolver" --layer "$repo_root" subject_pattern 2>/dev/null)" || layer=""
case "$layer" in
docs/conventions/source-control.local.yaml)
  owner="your personal convention"
  fix="edit $layer, which only you read"
  ;;
*)
  [ -n "$layer" ] || layer="the team convention file"
  owner="the team convention"
  fix="change it in $layer through a pull request"
  ;;
esac
{
  printf 'guardrails: the commit subject does not match %s.\n' "$owner"
  printf '  subject: %s\n' "$subject"
  printf '  pattern: %s   (subject_pattern in %s)\n' "$subject_ere" "$layer"
  echo "Rewrite the subject to match the pattern and commit again. If the pattern"
  printf 'itself is wrong, %s.\n' "$fix"
} >&2
exit 1
