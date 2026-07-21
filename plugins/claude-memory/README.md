# claude-memory

A Claude Code plugin that keeps a repo's Claude Code memory layer healthy and under your control.
It ships two skills:

| Skill | Question it answers |
|---|---|
| `/claude-memory:audit` | Is the instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`, auto-memory) healthy against official-doc criteria? |
| `/claude-memory:stateless` | Is Claude's auto memory on, where does it live, and how do I turn it off or wipe it? |

The two skills split by axis: `audit` checks the health of the instruction/memory layer; `stateless`
controls the on/off state and contents of the Claude-written auto-memory store. The configuration
FILES, automation SET, and permission GRANTS are audited by the sibling skills in the separate
`claude-config` plugin (`audit`, `automation-gaps`, `permission-hygiene`).

## What the skills do

### audit

Audits the files you write that shape Claude's behavior against a codified checklist derived from
official Claude Code documentation (line budgets, deletion test, content placement, consistency,
currency, auto-memory index integrity). A deterministic spine (script-backed checks for the MEMORY.md
index and orphan always-loaded rules) yields identical findings on identical repo state; judgment-tier
checks apply fixed criteria with model reading. Reports persist to the plugin's data directory — they
audit contributor-personal auto-memory, so they never land in the repo.

```shell
/claude-memory:audit          # audit (default)
/claude-memory:audit fix      # apply findings with per-item approval
/claude-memory:audit update   # refresh criteria from current official docs
/claude-memory:audit report   # show the last audit without re-running
```

### stateless

Inspects and disables Claude Code **auto memory** — the notes Claude writes for itself per repo at
`~/.claude/projects/<project>/memory/` (relocatable via `autoMemoryDirectory`). Scope is auto-memory
only: the instruction layer (`CLAUDE.md`, `.claude/rules/`) belongs to `audit`, and transcripts /
history are out of scope (Claude Code auto-cleans those via `cleanupPeriodDays`).

```shell
/claude-memory:stateless           # status (default) — effective on/off state + where the store lives
/claude-memory:stateless disable   # autoMemoryEnabled:false + CLAUDE_CODE_DISABLE_AUTO_MEMORY (scope-confirmed)
/claude-memory:stateless purge     # DESTRUCTIVE — delete auto-memory files after a confirmation gate
```

`disable` sets both the env var (authoritative — it overrides `autoMemoryEnabled` per the env-vars
doc) and the setting (persistent fallback); `purge` reads `autoMemoryDirectory` at every settings
scope before it enumerates what to delete, shows a manifest, and deletes only after explicit
confirmation. Claude Desktop / claude.ai
account memory is a separate server-side store — the skill gives direction to the app's Settings →
Memory controls rather than deleting it locally.

## Consumer conventions

The skill reads the consuming repo's own `CLAUDE.md` / `.claude/rules/` for project-specific
instruction-layer policy: a team-shared-first codification rule, an always-loaded context-budget
policy, or a documented exemption (e.g. a deliberate CLAUDE.md line-budget overage for a repo that runs
a large rules layer). Such findings are surfaced under a `REPO` check-ID so they stay distinct from the
doc-derived checks. Nothing project-specific is baked into the plugin.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install claude-memory@melodic-software
```

## Configuration

No `userConfig`. State: `audit` reports persist under the plugin's `${CLAUDE_PLUGIN_DATA}` directory —
they are contributor-local because they cover per-contributor auto-memory, so they never land in the
consuming repo. Side effects: `stateless disable` edits a `settings.json` you choose (setting
`autoMemoryEnabled` and an `env` var, then flagging a dotfile-manager backfill if the file is tracked);
`stateless purge` deletes auto-memory `*.md` files after a confirmation gate — both act only on the
scope you confirm. Network: the `audit update` action fetches official docs pages (read-only). Scripts
require `git` and standard shell utilities.

## License

MIT (SPDX-License-Identifier: MIT).
