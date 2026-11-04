#!/usr/bin/env bash
# A drafted PLAN.md awaiting approval. The prompt pastes a page-input block whose lock names a
# choice, "merge", that the plan view does not carry; the session must reject the block.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p .work/report-speed

cat >.work/report-speed/PLAN.md <<'MD'
# Plan: Faster account reports

**Status:** awaiting approval

## Goal
The reports page renders in under 5 seconds for the largest accounts.

## Phases

### Phase 1: Index report rows
Not started. Add an index on report_rows.account_id.
Accept when: the report query plan uses the index.
MD

git add .
git commit -q -m "docs: draft the report-speed plan"
