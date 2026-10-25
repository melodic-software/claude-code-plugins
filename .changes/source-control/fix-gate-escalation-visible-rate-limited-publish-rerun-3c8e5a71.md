---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`'s merge gate posts an escalation to a person (its risk, verifier, held-major and shared-copy escalations, written with the human-gated label) as a new comment instead of editing its earlier one. An edit sent no notification and kept the comment's old date, so the label stood with no visible reason. A reasons comment that is not escalated is still edited in place, and an unchanged escalation is not posted again.
- The merge gate's automatic re-run of a failed AI review check also fires when the lane's review post hit GitHub's API rate limit, on exactly the annotations the review evidence accepts a second attempt after, so the re-run's attempt binds. It was re-run only after `class=rate-limit`, which left such a check failed until a person re-ran it.
