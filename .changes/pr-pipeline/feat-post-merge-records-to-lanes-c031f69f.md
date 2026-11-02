---
bump: minor
---

### Changed

- `post-merge-demotion-alert.yml` treats a record as a state marker, never lane work: no record is sent to intake triage, and its text names each newly failing check by job name only and carries no revert command. A schedule or dispatch record, demotion or post-merge-failure, is filed with no `needs-human` label, since it clears itself once main is green at a later commit. Canary and revert records keep the label, since only a person's close clears one.
- A new `close-cleared` job runs on a green attempt 1 of a scheduled full run on main and closes as completed each open schedule or dispatch record, from `github-actions[bot]` or `merge.agent-identity`, created before that run, at a commit behind its head, and never edited.
- Each quarantine issue the suite judge files is locked and sent to intake triage. A quarantine or fix issue not delivered gets `needs-human`, the record does when no fix issue could be filed, and the job fails; a fix issue reopened on a repeat failure keeps its labels, so one labeled `needs-human` stays with a person.
- red-main plans no revert for a culprit whose guards fail; the fix issues fix main forward. The guards and the persisted `decision=human` token are unchanged.
