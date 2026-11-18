# context-budget

Measure a Claude Code session's fixed startup context payload **per item**, on your machine, at a
pinned binary, and record what every trim actually saved.

This plugin attributes the built-in tool pools, `System tools` and `System tools (deferred)`, per
tool, because `/context` reports them only as totals. The rest of the breakdown stays with the
built-in `/context` command; what it itemizes is read at its row in
[commands § All commands](https://code.claude.com/docs/en/commands#all-commands). The plugin
attributes the pools by A/B differencing: a baseline headless session versus one session per candidate
tool with that tool denied by bare name. The two attributed buckets compose differently:
deferred-side deltas add, so a basket's deferred saving is the sum of its members, while
prefix-side deltas double-count, so their sum is only an upper bound on the basket's prefix
saving.

## Install

```text
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context-budget@melodic-software
```

## Skills

- `/context-budget:setup`. Read-only prerequisite check: `node` (the engine's runtime), the
  `claude` CLI the engine measures against, and the optional Agent SDK that enables exact mode.
  Installs nothing. The guardrails plugin's settings-write ask covers the project settings
  `/context-budget:audit fix` edits.
- `/context-budget:audit`. Take a stamped baseline snapshot, attribute the built-in tool pools
  over the live tool list, present catalogue levers with their honesty categories, and ledger
  any before/after the operator produces. Read-only on bare invocation: it prints exact config
  (for persistent denies, a `permissions.deny` entry) and applies nothing. With the explicit
  `fix` argument, a guided per-lever walkthrough may edit **project** settings after per-diff
  approval. User-global `~/.claude/settings.json` is only ever printed, and every applied lever
  is re-measured and ledgered before the next.

## Live breakdown

A mod shows what the session's context is made of right now, by category, with each category's
tokens, share of the window and theme color. It needs Claude Code 2.1.287 or later; mods are
unsupported below that, and the plugin ships no shim
([ADR 0052](../../docs/adr/0052-adopt-claude-code-mods.md)).

The `live_display` option picks where it shows:

- `pane` (default). `/context-budget live` opens or closes a pane. Its header reads
  `◆ context <used> of <window> · compacts at <threshold> <percent>%`, with the "compacts at" part
  only when auto-compaction is on. Each category follows with its tokens, percent and color;
  deferred categories are listed dimmed with "deferred" in place of a percent. In a session drawn
  only in the Desktop app, the app's session details panel already shows this breakdown under
  Context, so `/context-budget live` and `live pane` open no pane there and a toast points to that
  panel and to `live band`.
- `band`. A bordered block of up to 5 rows above the prompt (header, bar, one-line legend), above
  other plugins' rows, fitted to the available width, and out of the way while a survey prompt
  shows. `/context-budget live` opens or closes the detail pane and leaves the band on;
  `/context-budget live off` hides the band. This multi-row band is an opt-in exception to
  the repository's one-row-per-mod display guidance
  ([mods](../user-interface/reference/types/mods.md)). In the Desktop app the band is one line:
  `Context <used> / <window> · <percent>%`, a colored bar with one segment per category, and on
  hover the segment darkens and its name, tokens and percent show at the right. The used figure
  takes the color of the zone context-usage publishes
  ([published zone](../context-usage/README.md#published-zone-for-status-lines)), and stays
  uncolored when no fresh zone is published for this session.
- `off`. Nothing shows and nothing is measured.

`/context-budget live pane`, `live band` and `live off` set the mode for the session and survive a
hot reload. In `off` mode, `/context-budget live` shows a toast that says how to turn the display
on.

**Skills warning.** When the Skills row holds 1% or more of the window, it shows in the warning
color. In the pane, a line under the row says so and names the fix: run `/skill-doctor`, or check
`skillListingBudgetFraction`. In the band, the Skills entry in the legend turns the same color, and
the pane carries the fix. The level is the skill listing's default budget, 1% of the context
window. Claude Code counts that budget in characters, sized from the window's tokens: the
documented fallback of 8,000 characters is 1% of a 200k window at 4 characters per token. So a
listing that fills the default budget is about 1% of the window in the tokens the row counts. With
`skillListingBudgetFraction` raised, the listing can pass 1% without being over its budget, so the
line states the row's share and does not say the listing is over a budget. The threshold is fixed,
with no option to change it. The row shows its percent rounded, so a Skills row at 0.6% reads "1%"
with no color. No other category has a documented level, so no other row warns. How full the
context is stays with `context-usage`.

- **Pointer:** [skills § Skill descriptions are cut short](https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short),
  and `SLASH_COMMAND_TOOL_CHAR_BUDGET` on [environment variables](https://code.claude.com/docs/en/env-vars)
  for the 8,000-character fallback.
- **As of:** 2026-10-31.
- **Recheck trigger:** either page changes the listing budget's default, unit or fallback, or what
  the Skills row in `/context` counts.

**Refresh and cost.** The mod reads Claude Code's local estimate of the breakdown, with no network
call, when you open or switch the view and, while it is shown, when context usage changes. `off`
makes no reads.

**States.** Before the first response, and right after a compaction, the pane says "waiting for
next response" and the band draws nothing. When no breakdown is available, the pane shows the basic
usage header and one "usage unavailable" line (the line alone when the basic figures fail too), and
the band draws nothing.

Tested in: the plugin test kit (terminal and desktop surfaces) on Claude Code 2.1.296, plus
`claude plugin validate` and `tsc`. No live interactive, `--bg` or Desktop session has run it yet.

## What makes the numbers trustworthy

- **No figures ship; every number is measured locally.** The skill contains no token figures, tool
  inventories, or thresholds. Those drift with every CLI release. Every number in a report was
  produced by a run on the consumer's machine during that audit.
- **Every report is stamped** with the measured binary path and version, the measurement mode,
  and the session kind. Machines with two CLI installs get an answer per binary, not a blend.
- **Comparability is enforced, not advised.** `System tools` deltas are only valid between runs
  with identical skill listings (why: `skills/audit/reference/engine.md` "Comparability rules");
  the engine fingerprints the listing per run and marks violating comparisons incomparable rather
  than reporting their numbers.
- **Levers are catalogued data.** Each row in
  `skills/audit/reference/levers.json` carries its honesty category (does it remove weight, work
  but save nothing here, block without saving, sit as vendor weight, or cost more than it buys),
  the official citation behind it, how to detect and measure it, the exact config it would emit,
  and a recheck trigger. A lever whose category cannot be determined for your configuration is
  not offered.
- **Honest degradation.** Exact mode uses the Agent SDK's structured context usage. Without the
  SDK, the engine parses headless `/context` output version-aware (display-rounded, and flagged
  as resting on a surface the docs do not list for `-p`; the record is under "Degradation ladder"
  in `skills/audit/reference/engine.md`). When neither works, it emits a structured error with a
  remediation, never a wrong number.

## Prerequisites

- `node` (required, the engine's runtime).
- The Claude Code CLI (`claude` on PATH, or pass the engine an explicit `--binary`); the live
  breakdown mod needs 2.1.287 or later.
- Optional, for exact mode: `@anthropic-ai/claude-agent-sdk`, installed once into the plugin's
  data directory (the audit skill offers the command; it is the operator's call since it needs
  network access).

## Data

Ledger and snapshots live under `${CLAUDE_PLUGIN_DATA}/audit/<state-key>/`, keyed per project by
the marketplace's shared state-key scheme, with one file per run plus an appended history line.
An uninstall can delete this directory; the audit tells the operator so near the ledger.

- **Pointer:** [plugins CLI reference § What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

## Boundaries

- Usage-based removal ("which plugins do I never use") belongs to the bundled `/doctor`; the
  skill routes there and never reimplements it.
  Pointer: <https://code.claude.com/docs/en/skills#check-your-setup-with-/doctor>.
- Which skills to turn off goes to the built-in `/skill-doctor`, which the person runs; the audit measures what a toggle saved and never picks the skill.
  Pointer: <https://code.claude.com/docs/en/skills#find-unused-skills>.
- Per-skill / per-agent / per-MCP-tool attribution belongs to `/context` natively.
- This plugin answers "what is my context made of": the startup measurement and the live
  breakdown. How full the context is and what happens as it fills (zones, notices to Claude,
  toasts, the one-line level row) belongs to the `context-usage` plugin.
- Measurements describe **headless** sessions of the **local CLI**; interactive sessions and
  cloud/web surfaces can compose the payload differently, and reports say so.

## Configuration

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `live_display` | string | `"pane"` | Where the live context breakdown shows. pane opens it in a pane when you run /context-budget live; band keeps it above the prompt; off shows nothing and measures nothing. /context-budget live pane, band or off changes it for the session. |

### How to set these

Set the options above for `context-budget@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
