---
bump: patch
---

### Changed

- The `code-reviewer` agent rates repetition the way `/review:quality-gate code-design` does: Duplicated Code the diff introduces in code, with no shared source or sync check keeping the copies aligned, is CRITICAL when the finding names the repeated fact and the later change that would make the copies diverge, and may then carry `Confidence: high` once verified at every copy. Shotgun Surgery and all other repetition stay SUGGESTION, as do Markdown and a `prototype` quality bar; other smells keep the advisory default, and the project's own severity vocabulary and criteria still win. With no `Quality bar:` line in its brief it rates as production and says so. Because the merge lane blocks on CRITICAL, an introduced, unsynced copy now blocks an unattended merge.
- `review:brief-reviewer` lists `code-design` among the `/review:quality-gate` modes that dispatch it.
