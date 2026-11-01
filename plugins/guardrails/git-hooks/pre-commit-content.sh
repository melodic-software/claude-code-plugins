#!/bin/sh
# guardrails-pre-commit-content v2
# guardrails pre-commit check: secrets and machine-specific paths in the lines
# this commit adds.
#
#   pre-commit-content.sh               the staged changes (git runs it as pre-commit)
#   pre-commit-content.sh --worktree    the uncommitted changes against HEAD,
#                                       untracked files included
#
# The write-path-independent layer for what the secret-pattern-detection and
# hardcoded-path-check guards stop on Write and Edit: a shell command, a script
# or another tool can write a file no Claude Code guard sees, and this check
# reads what reaches a commit. The scan is content-scan.sh, which says what it
# judges and skips; it and the pattern libraries it reads are installed beside
# this script as entry assets. The staged change is read from the index.
#
# Findings print as "<path>:<line>: <message>" on stderr and exit 1. The
# message says how to fix the content; this hook never suggests skipping it.
# A text tool that fails mid-scan also exits 1, since the scan is incomplete.
#
# POSIX sh until check-lib.sh, sourced first, has it running under bash.
# shellcheck shell=bash
case "$0" in
*/*) here="${0%/*}" ;;
*) here=. ;;
esac
lib="$here/check-lib.sh"
# shellcheck disable=SC2292 # still POSIX sh: no [[ ]]
[ -f "$lib" ] || lib="$here/../lib/git-hooks/check-lib.sh"
# shellcheck source=../lib/git-hooks/check-lib.sh
. "$lib" || exit 1
set -uo pipefail
# shellcheck source=content-scan.sh
. "$here/content-scan.sh" || exit 1

checks_init pre-commit "$@" || exit 0
content_scan_init
checks_changed_lines
content_scan "$CHECKS_TMP/blocking"
content_report "$CHECKS_TMP/blocking" 'the change (use a placeholder, an environment variable or a portable path)'
