#!/usr/bin/env bash
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
