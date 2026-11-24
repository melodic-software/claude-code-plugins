#!/bin/sh
# guardrails-pre-commit-content v2
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
while read -r head; do
  other_parents+=("$head")
done < <(checks_merge_heads)
checks_changed_lines
content_scan "$CHECKS_TMP/blocking"
content_report "$CHECKS_TMP/blocking" 'the change (use a placeholder, an environment variable or a portable path)'
