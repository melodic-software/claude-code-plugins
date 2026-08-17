# context-budget

Measure a Claude Code session's fixed startup context payload **per item**, on your machine, at a
pinned binary — and record what every trim actually saved.

`/context` already itemises skills, agents, and MCP tools. What it structurally cannot itemise is
the built-in tool pool: `System tools` and `System tools (deferred)` are lump sums, and together
they are typically the largest single contributor to the fixed payload. This plugin attributes
them per tool by A/B differencing — a baseline headless session versus one session per candidate
tool with that tool denied by bare name. The deltas are compositional, so a basket of trims can be
priced from its members.

## Install

```text
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context-budget@melodic-software
```

## Skill

- `/context-budget:audit` — take a stamped baseline snapshot, attribute the built-in tool pools
  over the live tool list, and ledger any before/after the operator produces. Read-only: it
  prints exact config (for persistent denies, a `permissions.deny` entry) and applies nothing.

## What makes the numbers trustworthy

- **Nothing is shipped, everything is measured.** The skill contains no token figures, tool
  inventories, or thresholds — those drift with every CLI release. Every number in a report was
  produced by a run on the consumer's machine during that audit.
- **Every report is stamped** with the measured binary path and version, the measurement mode,
  and the session kind. Machines with two CLI installs get an answer per binary, not a blend.
- **Comparability is enforced, not advised.** `System tools` deltas are only valid between runs
  with identical skill listings (listed skill frontmatter is subtracted from that bucket); the
  engine fingerprints the listing per run and marks violating comparisons incomparable rather
  than reporting their numbers.
- **Honest degradation.** Exact mode uses the Agent SDK's structured context usage. Without the
  SDK, the engine parses headless `/context` output version-aware (display-rounded, and flagged
  as resting on an undocumented surface). When neither works, it emits a structured error with a
  remediation — never a wrong number.

## Prerequisites

- `node` (required — the engine's runtime).
- The Claude Code CLI (`claude` on PATH, or pass the engine an explicit `--binary`).
- Optional, for exact mode: `@anthropic-ai/claude-agent-sdk`, installed once into the plugin's
  data directory (the audit skill offers the command; it is the operator's call since it needs
  network access).

## Data

Ledger and snapshots live under `${CLAUDE_PLUGIN_DATA}/audit/<state-key>/`, keyed per project by
the marketplace's shared state-key scheme, with one file per run plus an appended history line.
Uninstalling the plugin from its last scope deletes this directory unless `--keep-data` is
passed.

## Boundaries

- Usage-based removal ("which plugins do I never use") belongs to the bundled `/doctor`; the
  skill routes there and never reimplements it.
- Per-skill / per-agent / per-MCP-tool attribution belongs to `/context` natively.
- Live in-session occupancy zones belong to the `context-guard` plugin.
- Measurements describe **headless** sessions of the **local CLI**; interactive sessions and
  cloud/web surfaces can compose the payload differently, and reports say so.
