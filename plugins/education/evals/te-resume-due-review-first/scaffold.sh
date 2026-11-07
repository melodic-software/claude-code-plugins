#!/usr/bin/env bash
# Seeds the in-progress sql-joins workspace, then ages its learning records by ten months, in their
# mtimes and in a dated line a Read can see, so the INNER JOIN floor concept is due for review.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../control-resume-criteria-not-met/scaffold.sh"
records=learning/topic/sql-joins/learning-records
printf '\n**Date**: 2026-01-05\n' >>"$records/0001-starting-point.md"
printf '\n**Date**: 2026-01-05\n' >>"$records/0002-inner-join-demonstrated.md"
touch -d '2026-01-05' "$records"/*.md
