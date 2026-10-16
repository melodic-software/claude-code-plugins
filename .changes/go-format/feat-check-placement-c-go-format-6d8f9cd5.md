---
bump: minor
---

### Added

- A git pre-commit entry, `goimports-format`, that runs `goimports -w` over the staged Go files, re-stages them, refuses a partly staged file untouched, and blocks a commit only for a file goimports cannot parse, naming its line. A staged file since deleted from the work tree is parsed from the index, never rewritten or recreated. `/go-format:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The opt-in `go_format_end_of_turn` option: when a turn ends, the uncommitted Go files are parsed without rewriting, and a file goimports cannot parse is handed back, at most once per turn.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.

### Changed

- The per-edit `PostToolUse` row is replaced by one `PostToolBatch` row that runs `goimports -w` over every Go file a batch wrote, once, and prints nothing. A syntax error no longer reaches Claude on each edit; the pre-commit entry reports it.
- A file under `.githooks/` is never rewritten, and a file that only a `Read` named is never rewritten.

### Removed

- The per-edit syntax-error report, the rewrite disclosure, the missing-goimports notice on edit (the session-start probe still reports it), and the `SessionStart` row that reset the findings digest.

### Fixed

- A Go file whose block comment is followed by code on the same line, such as `/* license */ package p`, is no longer taken as generated because of a later `// Code generated ... DO NOT EDIT.` comment, matching `go/ast.IsGenerated`; it is formatted and checked like any other file.
