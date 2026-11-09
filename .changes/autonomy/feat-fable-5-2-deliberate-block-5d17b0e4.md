---
bump: patch
---

### Changed

- The autonomous-pipeline reminder adds a clause that keeps recovery from working past a deliberate block (a file marked not to be touched, access withheld on purpose, a safety guardrail): the run leaves it alone, says what it found, and looks for another safe way to finish. The README cites the Claude Fable 5.2 guide section it rests on.
