---
bump: patch
---

### Changed

- The `/plugin-quality:audit` command, config and hook lenses and its recurring-concerns checklist
  no longer restate upstream behavior (what a command file and a skill each produce, where a
  `sensitive` value is stored, which plugin `settings.json` keys take effect, how LSP entries
  fail, what a hook matcher matches, and whether `.claude/` is protected). Each keeps its own check
  and links the upstream section with an as-of date and a recheck trigger. The LSP check now
  validates each `.lsp.json` entry against the `lspServers` field table.
