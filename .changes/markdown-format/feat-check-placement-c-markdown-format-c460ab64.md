---
bump: minor
---

### Added

- A git pre-commit entry, `markdown-check`, that runs `markdownlint-cli2 --fix` over the staged Markdown, re-stages the rewrite, refuses a partly staged file untouched, and blocks a commit only on a finding markdownlint still reports on a line the commit adds. A staged file since deleted from the work tree is checked from the index, never rewritten or recreated, so a fixable finding on it is reported too. `/markdown-format:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The pre-commit entry refuses a commit while a markdownlint config above a staged Markdown file has an unstaged edit or deletion, naming the file, since markdownlint-cli2 reads the work tree's copy and the commit holds the index's.
- The opt-in `markdown_format_end_of_turn` option: when a turn ends, the same check runs over the uncommitted changes, without rewriting, and hands its findings back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.

### Changed

- The per-edit `PostToolUse` rows are replaced by one `PostToolBatch` row that rewrites every `.md` and `.mdc` file a batch wrote, once, and prints nothing. markdownlint findings no longer reach Claude on each edit; the pre-commit entry reports them.
- A markdownlint config that can run repository code (a `.cjs` or `.mjs` config, or one naming `customRules`, `markdownItPlugins` or `outputFormatters`) still runs only after the user approves its content state, now for the batch row and the pre-commit entry alike. The approval marker lives under the repository's git common directory (`markdown-format/trust-approvals`), no longer under `CLAUDE_PLUGIN_DATA`, so one approval covers the batch row, the end-of-turn row, an agent's commit and a person's, as powershell-format's does; markers are renamed with an `md-` prefix, so an approval made before this release must be made again. A person's commit names the marker to create; an agent commit never gets the command.
- The batch row rewrites only a file inside a git working tree (or `CLAUDE_PROJECT_DIR`). A file under `.githooks/` and a file that only a `Read` named are never rewritten.

### Removed

- The per-edit findings report, the missing-markdownlint and trust-gate notices on edit (the pre-commit entry reports the trust gate) (the session-start probe still reports a missing `markdownlint-cli2`), the telemetry envelope, and the `SessionStart` row that reset the findings digest.
- The `markdown_format_max_findings` option, which capped the per-edit report that no longer exists.
