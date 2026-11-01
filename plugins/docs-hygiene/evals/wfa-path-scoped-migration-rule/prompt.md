---
description: "Hard case. Why hard: the one rule an agent cannot derive (never edit a merged migration, because deployed checksums then fail) is an all-caps prohibition buried among derivable and no-op lines, and the rule should load only for migration work. A run must gate the file with Claude Code paths frontmatter (Cursor globs alone fails), keep the checksum reason, state the positive alternative, and cut the derivable lines. Written from the before SKILL.md contract"
tags: [write-for-agents, rules-file, path-scoped, hard]
runs: 3
max_turns: 10
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "One fenced rule file whose frontmatter scopes it with paths to db/migrations, whose body keeps the do-not-edit-merged-migrations rule with its checksum reason and the write-a-new-migration alternative, and which drops the location, naming, clean-SQL, down-file and be-careful lines"
---

Write this up as a .claude/rules file for our repo. It only matters when someone is working on the migrations under `db/migrations/`. The Makefile has the `migration` and `migrate-verify` targets, and CI already fails any migration that has no down file. Below is what the team posted in Slack; keep only what an agent could not work out from the repo itself. Reply with the rule file in full, frontmatter included, inside one ````markdown fenced block (four backticks, so any code example inside survives), then one line per thing you cut saying why.

```text
Migration rules (please read!!)

- Migrations live in db/migrations/ and are plain SQL files.
- File names start with a timestamp, like 20260114093000_add_invoice_status.sql. Use `make migration name=...` to create one; it fills in the timestamp.
- Write clean, well-formatted SQL.
- NEVER EVER edit a migration that has already been merged to main!!! (Staging and production have already applied it, and `make migrate-verify` compares the checksum of every applied file, so an edited file fails every deploy after it.)
- Every migration needs a matching down file, e.g. 20260114093000_add_invoice_status.down.sql.
- Be careful with migrations, they're important.
```
