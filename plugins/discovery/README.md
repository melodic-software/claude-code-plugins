# discovery

A Claude Code plugin for **structured discovery before changes** — understand what
IS (the local codebase) and what SHOULD BE (current external sources) before any
code is written. Four skills, two axes: local vs external, inline vs isolated.

| Skill | Axis | What it does |
|---|---|---|
| `/discovery:explore` | Local, inline | Six-dimension codebase exploration — code reading, git history, project structure, test discovery, build config, environment — plus a `blindspot` mode that surfaces the USER's unknown-unknowns and coaches a better prompt. |
| `/discovery:explore-deep` | Local, isolated | The same explore workflow in a forked subagent: verbose reads and search output stay in the fork; only a short summary returns, with findings persisted to `EXPLORE.md`. Requires `CLAUDE_CODE_FORK_SUBAGENT=1`. |
| `/discovery:research` | External, inline | Three chained research phases (broad → targeted + falsification → preferred sources) with per-claim source tiers, independent-corroborator ratios, a recency gate, and a binary outcome gate before presenting. |
| `/discovery:research-deep` | External, isolated | Dispatcher that routes deep research to the heaviest isolated tier available — a deep-research workflow engine, a forked subagent, or inline as last resort — with a multi-topic check that fans out one agent per separable topic. |

Both inline skills persist handoff artifacts (`EXPLORE.md` / `RESEARCH.md`) so a
fresh session can resume planning from the artifact alone.

## Works in any repo

- **Self-contained.** The research discipline file (source tiers, recency gates,
  falsification recipes, failure patterns) and the per-ecosystem discovery
  reference ship inside the plugin and are referenced via `${CLAUDE_PLUGIN_ROOT}`.
- **Reads your conventions, assumes none.** Project rules, preferred-source
  rosters, per-ecosystem source mappings, and any stated direction come from your
  own project's `CLAUDE.md` and rules; where none exist, the skills self-discover
  (llms.txt / sitemap probing, canonical-home identification).
- **Graceful degrade.** Adjacent capabilities — a workflow engine, forked
  subagents, synthesis MCP servers, documentation agents — are used when present
  and substituted when absent; no phase blocks on a missing tool, and substitutions
  are documented as gaps rather than silently lowering the bar.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install discovery@melodic-software
```

## Configuration

Artifact placement follows the marketplace **topic-docs convention** (`docs/conventions/topic-docs/`
in the melodic-software/claude-code-plugins repository). `EXPLORE.md` / `RESEARCH.md` are memory-tier
documents: they land in `<memory_dir>/<slug>/` (default `.work/<slug>/`), one slug per topic, never
committed — the memory root self-ignores. Skills resolve `<memory_dir>` in order: the tracked concern
file `.claude/topic-docs.yaml` → a working-docs convention in your own `CLAUDE.md` or rules → the
deprecated `notes_dir` option → an inferred conforming layout → one question → the `.work` default.
`/discovery:setup` is an idempotent interview that persists the concern file and migrates legacy
content.

| Option | Type | Status | Purpose |
|---|---|---|---|
| `notes_dir` | string | **Deprecated** — superseded by `.claude/topic-docs.yaml`; removed at the next major version | Legacy artifact directory (old default `.claude/notes`). When set — or when `.claude/notes/<slug>` content exists — skills keep reading and writing the old location until `/discovery:setup` migrates it. |

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
