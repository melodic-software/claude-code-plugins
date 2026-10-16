---
bump: minor
---

### Added

- A git pre-commit entry, `biome-check`, that runs `biome check --write` over the staged JavaScript, TypeScript and JSON files, re-stages them, refuses a partly staged file untouched, and blocks a commit only on a finding Biome still reports on a line the commit adds. A staged file since deleted from the work tree is checked from the index, never rewritten or recreated. `/biome-format:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The pre-commit entry refuses a commit while a `biome.json` or `biome.jsonc` above a staged file has an unstaged edit or deletion, naming the file, since Biome reads the work tree's copy and the commit holds the index's.
- The opt-in `biome_format_end_of_turn` option: when a turn ends, the same check runs over the uncommitted changes, without rewriting, and hands its findings back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.

### Changed

- The per-edit `PostToolUse` rows are replaced by one `PostToolBatch` row that rewrites every file a batch wrote, once per Biome config directory, and prints nothing. Lint findings no longer reach Claude on each edit; the pre-commit entry reports them.
- A file under `.githooks/` is never rewritten, and a file that only a `Read` named is never rewritten.
- The batch payload carries no pre-edit bytes, so a file that already drifted from the Biome config is formatted whole.

### Removed

- The per-edit findings report, the missing-biome notice on edit (the session-start probe still reports it), and the `SessionStart` row that reset the findings digest.
