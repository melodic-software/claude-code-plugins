---
bump: minor
---

### Changed

- `post-merge-demotion-alert.yml` treats a record as a state marker, never lane work: no record is sent to intake triage, and its text names each newly failing check by job name only and carries no revert command. A schedule or dispatch record, demotion or post-merge-failure, is filed with no `needs-human` label, since it clears itself once main is green at a later commit, and the next green scheduled run closes it as completed. Canary and revert records keep the label, since only a person's close clears one. Each quarantine issue the suite judge files is locked and sent to intake triage; a quarantine or fix issue not delivered gets `needs-human`, and the job fails.
- red-main plans no revert for a culprit whose guards fail; the fix issues fix main forward. The guards and the persisted `decision=human` token are unchanged.
