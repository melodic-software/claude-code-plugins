---
bump: minor
---

### Changed

- **babysit-prs**: `babysit_postmerge.py --remediate` files a schedule or dispatch demotion record with no human-gated label, since it clears itself once main is green at a later commit; a canary or read-back record keeps the label. Intake triage reads every issue the lanes App opens, so a record's detail names each newly failing check by job name only and the record carries no `git revert` command. A suite quarantine issue is filed with no label and no assignee, so intake triage hands it to a lane, and no longer goes to the suite's CODEOWNERS user.
