---
bump: minor
---

### Added

- The write tier, off by default ([#11228](https://github.com/melodic-software/claude-code-plugins/issues/11228)). A `write` tool runs one `INSERT`, `UPDATE`, `DELETE` or `MERGE` in one batch that commits only when `@@ROWCOUNT` equals the `expectedRows` argument and rolls back otherwise, so no transaction stays open between calls. It carries `_meta["anthropic/requiresUserInteraction"]: true`, so Claude Code asks a person on every call in every permission mode. It refuses every call unless the registration is started with `--write` and its environment has a `write` block naming a write principal separate from the read one; the server refuses a `write` block that reuses the read principal's variables or Entra identity.
- A `preview_write` tool, which lists the triggers on a table, the foreign keys whose `ON DELETE` or `ON UPDATE` action cascades from it, and the triggers on each table a cascade reaches, since the row-count check covers only the target table. It runs as the read principal.
- A write reject list (`checkWriteStatement` in `src/statement.mjs`), a heuristic that refuses every other statement kind, a second statement (a `SELECT` after `INSERT ... VALUES` included), transaction control, `SELECT ... INTO`, `OUTPUT` and the `OPENROWSET` family.
- An amendment to ADR 0086 recording the write-tier decisions.

### Changed

- Every registration now lists five tools instead of three, the same list whether or not it opted in to writes. The `query`, `list_objects`, `describe_object` and `preview_write` tools stay unflagged.
