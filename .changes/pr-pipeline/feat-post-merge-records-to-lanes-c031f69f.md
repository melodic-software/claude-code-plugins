---
bump: minor
---

### Changed

- `post-merge-demotion-alert.yml` treats a record as a state marker, never lane work: no record is sent to intake triage, and its text names each newly failing check by job name only and carries no revert command. A schedule or dispatch record, demotion or post-merge-failure, is filed with no `needs-human` label unless a failing check got no fix issue (over the cap or outside the name charset), since it clears itself once main is green at a later commit. Canary and revert records keep the label, since only a person's close clears one.
- A new `close-cleared` job runs on a green attempt 1 of a scheduled full run on main and closes as completed each open schedule or dispatch record, from `github-actions[bot]` or `merge.agent-identity`, created before that run, at a commit behind its head, and never edited.
- Each quarantine issue the suite judge files is locked and sent to intake triage. A quarantine or fix issue not delivered gets `needs-human`, the record does when a failing check got no fix issue, whether over the cap, outside the charset, or not filed, and the job fails on an undelivered issue; a fix issue reopened on a repeat failure keeps its labels, so one labeled `needs-human` stays with a person.
