#!/usr/bin/env bash
# Set one checklist line in the current branch's sweep PR body (grammar:
# ../SKILL.md "Formats").
#
#   tick.sh <id> in-progress
#   tick.sh <id> [--partial <detail>] committed <sha> <skill@version>...
#   tick.sh <id> no-findings <skill@version>...
#   tick.sh <id> partial <detail> <skill@version>...     zero findings, partial coverage
#   tick.sh <id> not-applicable <evidence>                records no skill version
#   tick.sh <id> [--partial <detail>] report-only <n> <skill@version>...
#   tick.sh <id> [--partial <detail>] declined <n> <skill@version>...
#   tick.sh <id> [--partial <detail>] filed <issue-url> <skill@version>...
#
# Reads the body with `gh pr view --json body`, writes it with `gh pr edit --body-file -`,
# re-reads it, and prints the new line. Only the first line for <id> between the repo-sweep
# markers changes; every other line keeps its bytes, CRLF included. A "[ ]", "[~]", or bare
# "[x]" line can be set; a done line cannot. No lock: one session per sweep.
# Exit: 0 ok; 1 line missing or already done, or the edit did not land (any other non-zero
# code is a failed gh or jq); 2 usage.
set -euo pipefail

# A native jq.exe under Git Bash or Cygwin writes text-mode stdout, which would add a CR to
# every line of the body and break the CRLF-preserving rewrite below; -b keeps the bytes.
# Pointer: https://jqlang.org/manual/#invoking-jq (--binary), as of 2026-10-11; recheck
# when jq changes how it opens streams on Windows. REPO_SWEEP_OSTYPE is the test seam for the platform.
case ${REPO_SWEEP_OSTYPE:-${OSTYPE-}} in
msys* | cygwin*) type -P jq >/dev/null && jq() { command jq -b "$@"; } ;;
*) ;;
esac

usage() {
  printf 'usage: tick.sh <id> in-progress\n       tick.sh <id> [--partial <detail>] committed <sha> <skill@version>...\n' >&2
  printf '       tick.sh <id> no-findings <skill@version>...\n' >&2
  printf '       tick.sh <id> partial <detail> <skill@version>...\n' >&2
  printf '       tick.sh <id> not-applicable <evidence>\n' >&2
  printf '       tick.sh <id> [--partial <detail>] report-only <n> <skill@version>...\n' >&2
  printf '       tick.sh <id> [--partial <detail>] declined <n> <skill@version>...\n' >&2
  printf '       tick.sh <id> [--partial <detail>] filed <issue-url> <skill@version>...\n' >&2
  exit 2
}
(($# >= 2)) || usage
id=$1 mode=$2
shift 2
cover=""
if [[ $mode == --partial ]]; then
  [[ ${1-} == ?* && $1 != *","* && ${2-} =~ ^(committed|report-only|declined|filed)$ ]] || usage
  cover=", partial coverage: $1" mode=$2
  shift 2
fi
suffix=""
case $mode in
in-progress) (($# == 0)) || usage ;;
committed)
  [[ ${1-} =~ ^[0-9a-f]{7,40}$ ]] || usage
  suffix=", committed $1$cover"
  shift
  ;;
no-findings) suffix=", no findings" ;;
partial)
  [[ ${1-} == ?* && $1 != *","* ]] || usage
  suffix=", no findings, partial coverage: $1"
  shift
  ;;
not-applicable)
  [[ $# == 1 && $1 == ?* && $1 != *","* ]] || usage
  suffix="not applicable: $1"
  shift
  ;;
report-only)
  [[ ${1-} =~ ^[0-9]+$ ]] || usage
  suffix=", no fix-eligible findings ($1 report-only)$cover"
  shift
  ;;
declined)
  [[ ${1-} =~ ^[0-9]+$ ]] || usage
  suffix=", findings declined ($1)$cover"
  shift
  ;;
filed)
  [[ ${1-} =~ ^https?://[^[:space:],]+$ ]] || usage
  suffix=", filed $1$cover"
  shift
  ;;
*) usage ;;
esac
versions=""
if [[ $mode != in-progress && $mode != not-applicable ]]; then
  (($#)) || usage
  for v in "$@"; do
    [[ $v == ?*@?* && $v != *[[:space:],]* ]] || usage
    versions=${versions:+$versions, }$v
  done
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The body stays in files: Git Bash's command substitution drops CRs.
gh pr view --json body | jq -j .body >"$tmp/old"
rc=0
awk -v id="$id" -v mode="$mode" -v done_text="$versions$suffix" -v newf="$tmp/new" '
  { cr = sub(/\r$/, "") }
  /^<!-- repo-sweep:begin / { inb = 1 }
  /^<!-- repo-sweep:end -->/ { inb = 0 }
  inb && !hit && match($0, /^- \[[ ~xX]\] /) {
    rest = substr($0, 7); i = index(rest, ": ")
    if (i && substr(rest, 1, i - 1) == id) {
      hit = 1; tail = substr(rest, i + 2)
      if (substr($0, 4, 1) ~ /[xX]/ && tail ~ /(, committed [0-9a-f]+|, no findings|, no fix-eligible findings \([0-9]+ report-only\)|, findings declined \([0-9]+\)|, filed [^ ,]+)(, partial coverage: .+)?$|(^|, )not applicable: .+$/) { done = 1; exit }
      $0 = mode == "in-progress" ? "- [~] " id ": " tail : "- [x] " id ": " done_text
      print > newf
    }
  }
  { printf "%s%s%s", sep, $0, cr ? "\r" : ""; sep = "\n" }
  END { if (done) exit 4; if (!hit) exit 3 }' "$tmp/old" >"$tmp/body" || rc=$?
case $rc in
0) ;;
3) printf 'tick.sh: no checklist line for %s\n' "$id" >&2 && exit 1 ;;
4) printf 'tick.sh: %s is already done\n' "$id" >&2 && exit 1 ;;
*) exit "$rc" ;;
esac
new=$(cat "$tmp/new")
gh pr edit --body-file - <"$tmp/body" >/dev/null
# shellcheck disable=SC2310 # jq may be the one-command -b wrapper above; errexit inside it changes nothing
if ! gh pr view --json body | jq -r .body | tr -d '\r' | grep -Fqx -- "$new"; then
  printf 'tick.sh: edit did not land: %s\n' "$new" >&2
  exit 1
fi
printf '%s\n' "$new"
