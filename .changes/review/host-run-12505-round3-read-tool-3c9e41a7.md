---
bump: patch
---

### Fixed

- The `code-reviewer` agent now reads its bundled files (`context/severity.md`, the quality-gate code-design criteria and the other `${CLAUDE_PLUGIN_ROOT}` files it names) with the `Read` tool instead of a shell `cat` or `sed`. Shell reads of those files were denied in eval runs, which made the reviewer-diversity suites invalid.
