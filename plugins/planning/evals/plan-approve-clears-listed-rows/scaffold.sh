#!/usr/bin/env bash
set -euo pipefail

mkdir -p .work/report-speed
cat >.work/report-speed/PLAN.md <<'MD'
# Plan: Faster account reports

**Status:** awaiting approval

## Goal
The reports page renders in under 5 seconds for the largest accounts.

## Phases

### Phase 1: Index report rows
Not started. Add a composite index on report_rows (account_id, created_at).
Accept when: the report query plan uses the index.

### Phase 2: Cache rendered reports
Not started. Cache each rendered report for 15 minutes. Depends on: Phase 1.
Accept when: a second load within 15 minutes is served from the cache.
MD
cat >.work/report-speed/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Open-question register

- Q1 | answered | round 1 | What is slow? | the reports page for accounts with over a million rows
- Q2 | superseded-by-plan | round 1 | How long may a rendered report be cached? | plan proposes: 15 minutes; was: one hour
- Q3 | answered | round 2 | Who reads the reports? | account admins
- Q4 | superseded-by-plan | round 2 | Which index is added? | plan proposes: a composite index on account_id and created_at; was: one index on account_id
MD
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
git add .
git commit -q -m "docs: draft the report-speed plan"
