#!/usr/bin/env bash
# Usage: check-body-sections.sh <heading>... < body
# Judges the PR body on stdin with the shared hook checker
# (hooks/pr-linkage-validator.sh): comments stripped, code masked, then each
# <heading> must be a present, non-empty `## <heading>` section. Prints one line
# per problem on stderr. Exit 0 when every heading passes (or none is given),
# 1 when any is missing or empty.
# No -e: the sourced checker counts with `((i++))`, which returns 1 at zero.
set -uo pipefail
export LC_ALL=C

# shellcheck source=../../../hooks/pr-linkage-validator.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../hooks/pr-linkage-validator.sh"

body=$(cat)
stripped=""
masked=""
strip_html_comments_to stripped "$body"
mask_markdown_code_to masked "$stripped"
LINKAGE_PROBLEMS=()
linkage::section_problems "$masked" "$@"
((${#LINKAGE_PROBLEMS[@]} == 0)) && exit 0
printf '%s\n' "${LINKAGE_PROBLEMS[@]}" >&2
exit 1
