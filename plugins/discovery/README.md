# discovery

A Claude Code plugin for **structured discovery before changes** — understand what
IS (the local codebase) and what SHOULD BE (current external sources) before any
code is written. The explore/research skills sit on the local vs external axis and
**dispatch a purpose-built subagent by default**, so the reading stays out of the
main conversation; `blindspot` is the fourth skill, serving the USER's
understanding rather than the agent's.

| Skill | Axis | What it does |
|---|---|---|
| `/discovery:explore` | Local | Six-dimension codebase exploration — code reading, git history, project structure, test discovery, build config, environment — persisting an `EXPLORE.md` index plus sidecars. Dispatches `discovery:explorer` by default. |
| `/discovery:research` | External | Corpus enumeration, then three chained research phases (broad → targeted + falsification → preferred sources) with per-claim source tiers, independent-corroborator ratios, a recency gate, a coverage ledger, and a binary outcome gate before presenting. Dispatches `discovery:researcher` by default. |
| `/discovery:research-deep` | External, tiered | Dispatcher that routes deep research to the heaviest isolated tier available — a deep-research workflow engine, a subagent, or inline as last resort — with a multi-topic check that fans out one agent per separable topic. Runs in main context itself, because a subagent cannot reach the `Workflow` tool. |
| `/discovery:blindspot` | Local, user-facing | Surfaces the USER's unknown-unknowns before they work in unfamiliar territory (a codebase area or a domain vocabulary), emitting blindspot cards and coaching one improved prompt. Deliverable is the user's understanding, not `EXPLORE.md`. |

| Agent | Dispatched by | What it does |
|---|---|---|
| `discovery:explorer` | `/discovery:explore` | Runs the six dimensions in a fresh context, loads path-scoped project rules explicitly, writes the artifact set, returns a bounded summary and a file pointer. |
| `discovery:researcher` | `/discovery:research` | Runs the full research discipline in a fresh context, writes the artifact set and coverage ledger, returns a file pointer plus a verification request. |

The two artifact-persisting skills (`/discovery:explore`, `/discovery:research`)
persist handoff artifacts (`EXPLORE.md` / `RESEARCH.md`) so a fresh session can
resume planning from the artifact alone. Each is **always an index**, with content
in sibling sidecars carrying a machine-readable header, so a consumer greps the
index and reads exactly the one section it needs.

Both skills document an **inline escape hatch** and the conditions under which it
is correct — tight turn-by-turn iteration, cost on a lookup too small to justify
the dispatch, or an invoking context that is itself a subagent. Running inline
relaxes no discipline.

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

Artifact placement follows the marketplace **topic-docs convention**
(<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>).
`EXPLORE.md` / `RESEARCH.md` are memory-tier
documents: they land in `<memory_dir>/<slug>/` (default `.work/<slug>/`), one slug per topic, never
committed — the memory root self-ignores. Skills resolve `<memory_dir>` in order: the tracked concern
file `.claude/topic-docs.yaml` → a working-docs convention in your own `CLAUDE.md` or rules → an
inferred conforming layout → one question → the `.work` default.
`/discovery:setup` is idempotent: `check` (default) reports the effective concern read-only, and
`apply` persists it — non-interactively from `<key>=<value>` arguments, or via a one-question
interview.

## License

MIT (SPDX-License-Identifier: MIT).
