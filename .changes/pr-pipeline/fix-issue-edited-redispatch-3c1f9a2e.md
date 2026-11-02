---
bump: patch
---

### Fixed

- The issue lane no longer hands an issue to a person with `reason=security` when its title or body changed after `agent-ready` and every change came from a listed human or one of our listed Apps. `write-issue` reads the account behind each body edit and title change after the label and refuses with `edited-trusted`, which routes the new `issue-edited-trusted` stop through intake: `agent-ready` and `status: ready` come off, so the triage sweep refines and admits the edited text again. A change by any other account, one whose account cannot be read, or one a truncated page may hide still holds as `issue-edited` with the `needs-human` security escalation.
