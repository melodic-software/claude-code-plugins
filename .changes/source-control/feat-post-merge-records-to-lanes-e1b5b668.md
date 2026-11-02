---
bump: minor
---

### Changed

- **babysit-prs**: a demotion record `babysit_postmerge.py --remediate` files keeps the human-gated label, which holds intake admission off the lanes App's issue, and its text keeps the fix-issue rule: the detail names each newly failing check by job name only, never a gate's annotation title, and the record carries no `git revert` command. The record says how it clears: a schedule or dispatch record once a full run passes on main at a later commit, any other only on a person's direct close. A suite quarantine issue is filed with no label and no assignee, so intake triage hands it to a lane, and no longer goes to the suite's CODEOWNERS user.

### Fixed

- **babysit-prs**: the merge gate reads the green full runs that clear a red-main record one week at a time from the record, oldest first, and stops at the first week that clears it. A record that cleared long ago no longer overflows the 500-run listing and demotes again while main is green.
