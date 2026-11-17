---
bump: minor
---

### Changed

- The `ecosystem-specialist` agent ships no build, test or lint commands of its own. A phase that neither the repository's `.claude/ecosystems/<ecosystem>.yaml` record nor its documented conventions resolve is reported `UNVERIFIED (unresolved)`, naming what the agent read. A changed file that no record's globs cover is placed by what the repository's own files imply for its path, or listed as unclassified. The plugin carries version 1.1.0 of the ecosystem resolution steps (`reference/ecosystem-resolution.md`), and the agent's report-format example uses placeholders.

### Removed

- The agent's file-extension-to-ecosystem table and its fallback commands for each ecosystem.
- Tool- and language-specific examples in model-read review text: the cast and debug-output examples in the `code-reviewer` agent's checklist, the named scanner in `quality-gate` security mode's after-review advice, and the probe command example in `quality-gate` downstream mode. The rules around them are unchanged.
