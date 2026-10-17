---
bump: minor
---

### Added

- `/instruction-placement:check` fails a `.claude/rules/` file whose YAML frontmatter will not parse. Claude Code ignores such frontmatter and loads the rule as if it had no `paths`, so the rule silently applies to every session. `glob-tools.sh rules` prints a `FRONTMATTER` row per file (line and reason) and exits 1. It screens for a tab in indentation, a plain value starting with `*`, `@` or a backtick (the unquoted `paths: **/*.ts`), and a plain value holding a colon followed by a space or ending in a colon; it is not a full YAML parser.

### Changed

- The routing rubric names a path-scoped skill (a `SKILL.md` with `paths:`) as a destination for procedure content scoped to file types; constraints stay in rules. It records that the deny on routing file-creation rules to `paths:` stays until a canary measures whether a Write-triggered rule arrives before the file is written.
