#!/usr/bin/env bash
# Seeds a resumed interview ledger whose constraints, answers and session shorthand are all referred to by code.
set -euo pipefail

mkdir -p .work/review-reruns
cat >.work/review-reruns/interview-checklist.md <<'MD'
# /planning:interview Checklist

## Constraint ledger

- C1 | confirmed | no new required status checks; ci-status stays the only required check | user, round 1
- C2 | confirmed | a review re-runs only when the head SHA changes | user, round 1
- C3 | confirmed | scoped change: one plugin, no shared workflow edits | user, round 2

## Starting point

- The user owns the PR pipeline and knows its lanes; the reviewer of this round does not.

## Open-question register

- Q1 | answered | round 1 | Which lane re-runs the AI reviews? | the pr-merge lane
- Q2 | answered | round 1 | What triggers a rerun? | a new head SHA on the PR
- Q3 | answered | round 2 | Does a rerun block the merge? | no; reruns are advisory
- Q4 | answered | round 2 | Where do rerun results show? | one PR comment, edited in place
- Q5 | open | round 2 | How many reruns per PR before the lane stops rerunning? |

**Session shorthand:**
- rerun: one more pass of both AI reviews on the PR's new head SHA
- R-cap: the most reruns one PR gets before the pr-merge lane stops rerunning

## Decision tree (`me` mode only)

- [x] which lane reruns: the pr-merge lane (Q1)
- [x] trigger: a new head SHA (Q2)
- [x] blocking: advisory only (Q3)
- [x] where results show: one edited PR comment (Q4)
- [ ] R-cap value (Q5)
- [ ] whether a force-push that keeps the same tree resets the R-cap (blocked by: Q5)
- [ ] what the lane does when a rerun finds a new blocking issue it cannot block on (rests on Q3 and C1)
MD
