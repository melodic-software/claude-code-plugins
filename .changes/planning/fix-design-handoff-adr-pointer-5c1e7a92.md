---
bump: patch
---

### Changed

- `/planning:design-handoff` no longer carries its own copy of the ADR admission test. Its "ADR candidates" entry lists each resolved decision whose thread records a rejected alternative, quoting that alternative, and offers `/architecture:record-decision` for each; that skill applies the test. Without the `architecture` plugin the decisions are listed for a human to judge.
