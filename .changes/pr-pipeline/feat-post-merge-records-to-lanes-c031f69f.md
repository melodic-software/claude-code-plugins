---
bump: minor
---

### Changed

- `post-merge-demotion-alert.yml` files a schedule or dispatch record, demotion or post-merge-failure, with no `needs-human` label, since it clears itself once main is green at a later commit; canary and revert records keep the label. No record is sent to intake triage: the fix issues carry the work. Each quarantine issue the suite judge files is locked and sent to intake triage, and one not sent fails the job.
- red-main plans no revert for a culprit whose guards fail; the fix issues fix main forward. The guards and the persisted `decision=human` token are unchanged.
