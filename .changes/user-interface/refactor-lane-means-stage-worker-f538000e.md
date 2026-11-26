---
bump: patch
---

### Changed

- **`/user-interface:audit` runs one concern at a time.** The skill, its references and its schema
  descriptions say "concern" where they said "concern lane", since "lane" now means only a worker
  that serves one pipeline stage. The arguments and the concern table are unchanged.
