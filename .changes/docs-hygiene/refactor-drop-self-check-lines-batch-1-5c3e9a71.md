---
bump: patch
---

### Changed

- write-for-humans no longer tells the model to re-read its finished draft

  The "After writing" bullet that asked for one more read of the draft
  as a newcomer is gone: Claude Opus 5 checks its own work unprompted,
  and the instruction caused over-verification. Its precedence rule
  (revert a rule's edit that leaves a sentence harder to read) now
  opens "Write the sentences" as a drafting rule. The prose linter and
  AI-tell checks, which produce new evidence, stay.
