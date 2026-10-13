---
bump: patch
---

### Changed

- **`/work-items:decompose` publishes a one-unit plan as one slice ([#6921](https://github.com/melodic-software/claude-code-plugins/issues/6921)).** A plan handed to a later session, an AFK lane or another person is still decomposed, as one slice that keeps Step 3's approval and carries the acceptance criteria and the quoted design part.
