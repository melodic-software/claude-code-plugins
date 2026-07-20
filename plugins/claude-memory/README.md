# claude-memory

A Claude Code plugin that keeps a repo's instruction/memory layer healthy. It ships one skill:

| Skill | Question it answers |
|---|---|
| `/claude-memory:audit` | Is the instruction/memory layer (`CLAUDE.md`, `CLAUDE.local.md`, `.claude/rules/`, auto-memory) healthy against official-doc criteria? |

The configuration FILES, automation SET, and permission GRANTS are audited by the sibling skills in the
separate `claude-config` plugin (`audit`, `automation-gaps`, `permission-hygiene`).

## What the skill does

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

No `userConfig`. State: audit reports persist under the plugin's `${CLAUDE_PLUGIN_DATA}` directory —
they are contributor-local because they cover per-contributor auto-memory, so they never land in the
consuming repo. Network: the `update` action fetches official docs pages (read-only). Scripts require
`git` and standard shell utilities.

## License

MIT (SPDX-License-Identifier: MIT).
