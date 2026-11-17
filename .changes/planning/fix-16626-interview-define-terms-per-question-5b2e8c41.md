---
bump: patch
---

### Fixed

- **`/planning:interview`, per-question terms.** Each question's `Context:` block gives one cited
  `term: definition` line per term the question relies on, counting every terminology-matrix or
  shorthand-glossary term anywhere in the question, one inside another term's definition included, even
  when an earlier question defined it. The checks run before a round is sent re-read each question for
  those terms.
