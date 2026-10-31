# context-budget

Measure a Claude Code session's fixed startup context payload **per item**, on your machine, at a
pinned binary, and record what every trim actually saved.

Per-skill, per-agent, and per-MCP-tool attribution stays with the built-in `/context` command.
This plugin covers what our measurements see `/context` report only as totals: the built-in tool
pools, `System tools` and `System tools (deferred)`. Together they are typically the largest
single contributor to the fixed payload, which is why the plugin targets them. It attributes them
per tool by A/B differencing: a baseline headless session versus one session per candidate
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

- `/context-budget:check`. Read-only check that `node` resolves for the hook and the engine, so
  it can run unprompted when a hook notice says `node` is missing. Installs nothing.
- `/context-budget:setup`. Read-only prerequisite check: `node` (the hook launches it by bare
  name, and a launch failure is non-blocking, so the checkpoint can be configured on yet never
  fire), the `claude` CLI the engine measures against, the optional Agent SDK that enables exact
  mode, and the effective `settings_write_ask_enabled` value. Installs nothing.
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
  deferred categories are listed dimmed with "deferred" in place of a percent.
- `band`. A bordered block of up to 5 rows above the prompt (header, bar, one-line legend), above
  other plugins' rows, fitted to the available width, and out of the way while a survey prompt
  shows. `/context-budget live` opens or closes the detail pane and leaves the band on;
  `/context-budget live off` hides the band. This multi-row band is an opt-in exception to
  the repository's one-row-per-mod display guidance
  ([mods](../user-interface/reference/types/mods.md)).
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
context is stays with `context-guard`.

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

## Hook

A PreToolUse checkpoint returns `permissionDecision: "ask"` when a **file-editing tool call**
(`Write`, `Edit`, `NotebookEdit`) targets a Claude Code settings file, so those
edits prompt even in auto mode. It matches only the settings files Claude Code reads:
`settings.json` in the user settings directory (`CLAUDE_CONFIG_DIR`, else `~/.claude`),
`settings.json` and `settings.local.json` in `.claude/` under the project directory or the
session's working directory, `settings.local.json` at the main checkout's root, plus
`managed-settings.json` and `managed-settings.d/` drop-ins in the managed system directory. A
fixture or example named `.claude/settings.json` elsewhere does not prompt. Kill switch: the
`settings_write_ask_enabled` plugin option.

- **Pointer:** where Claude Code keeps each settings file:
  [settings § Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
  and
  [§ Where Claude Code keeps the local file in a git repository](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository);
  for managed files,
  [managed settings § Where each mechanism stores the policy](https://code.claude.com/docs/en/managed-settings#where-each-mechanism-stores-the-policy).
- **As of:** 2026-10-11.
- **Recheck trigger:** any of these sections moves a settings file or adds one.

It is a checkpoint, not a guarantee: other hooks, settings, and permission modes decide what
happens to its `ask`. We state that whenever we describe the protection, and read the specifics
live:

- **Pointer:** [hooks § PermissionRequest](https://code.claude.com/docs/en/hooks#permissionrequest),
  [settings reference § `disableAllHooks`](https://code.claude.com/docs/en/settings-reference#disableallhooks),
  [Agent SDK permissions § Bypass permissions mode](https://code.claude.com/docs/en/agent-sdk/permissions#bypass-permissions-mode-bypasspermissions)
  (hook evaluation order against the mode check), and
  [headless § Turn off permission prompts in unattended runs](https://code.claude.com/docs/en/headless#turn-off-permission-prompts-in-unattended-runs)
  (what a `-p` run does with a call that would prompt).
- **As of:** 2026-10-11.
- **Recheck trigger:** any of these sections changes who can answer or skip a hook's `ask`, or a
  release note names hook evaluation order or `disableAllHooks`.

A mod (this plugin's or any other installed one) can keep `PreToolUse` settings hooks such as this
plugin's settings-write checkpoint from running: they run after the last
mod calls `next`, so a mod that answers a `tool.call` without calling it skips them
([where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)).
A mod can also approve a call they blocked, because its `tool.check` hook runs after them
([approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).
As of 2026-10-11. Recheck when either section moves settings hooks relative to the mod chain.

**What it does not see.** The checkpoint matches tool names and file paths, not the file on
disk. These routes change a settings file without an ask:

- A write through the shell: a redirect, a heredoc, `sed -i`, `cp`, `tee`, or a script run by
  `Bash` or `PowerShell`. None of them passes through a file-editing tool.
- A tool that renders configuration into place from a source elsewhere, such as a dotfile manager
  applying a template or symlink. That write is a legitimate action by another program, inside the
  session or outside it.

Claude Code's `ConfigChange` hook event fires on a settings change whatever wrote the file, but it
reacts after the write rather than asking before it. That is a different control from this one,
and this plugin does not register it.

- **Pointer:** [hooks § ConfigChange](https://code.claude.com/docs/en/hooks#configchange) and
  [§ ConfigChange decision control](https://code.claude.com/docs/en/hooks#configchange-decision-control);
  for what a PreToolUse matcher filters on,
  [hooks § Matcher patterns](https://code.claude.com/docs/en/hooks#matcher-patterns).
- **As of:** 2026-10-11.
- **Recheck trigger:** those sections give `ConfigChange` an `ask` outcome or a visible message,
  or the Matcher patterns section gives PreToolUse a matcher on target path.

**Decision (#3864): the claim is narrowed, and the hook is not widened.** Adding the shell lane
would put an always-on `Bash|PowerShell` hook under the
[hook-budget](../../docs/contracts/hook-budget/README.md) ceiling on every shell call in every
consumer. It would recognize a settings write only by guessing from the command string, and it
would still miss the render-into-place route. So even after paying that cost, the checkpoint could
not honestly claim every settings write. The `/context-budget:audit fix` path edits project
settings through a file-editing tool, so the checkpoint does cover this plugin's own write path.
Treat a future audit that finds this gap as re-filing it, not as a new defect.

The registration carries no `if` filter, so the hook process spawns on every matched write and the
script decides. An `if` gate was evaluated for this row and rejected. A probe on Claude Code 2.1.285
on Windows (2026-09-30) found that in a hook `if`, an `Edit(...)` rule does not match a Write tool
call at any path tested, inside or outside the working directory. `Write(...)` and `Edit(...)`
rules each match absolute paths outside cwd for their own tool, under every form tested: the
home-relative `~/`, the root-anchored `//`, the drive-letter spelling, the root-anchored recursive
glob, and an unanchored `*.json`. An earlier probe on 2.1.258 (2026-09-02) attributed the skipped
rules to the path; on 2.1.285 the path is not the cause, and 2.1.258 was not re-probed. Permission
rules differ: there, an `Edit` rule covers every built-in file-editing tool. One `Edit(...)` gate on
this `Write|Edit|NotebookEdit` row would therefore drop every Write silently, which is the opposite
of what the checkpoint exists to do. The row stays unconditioned; splitting it into a gated row per
tool needs its own probe, and NotebookEdit was not probed.

- **Pointer:** [hooks § Common fields](https://code.claude.com/docs/en/hooks#common-fields) (`if`
  uses permission rule syntax) and
  [permissions § What `Read` and `Edit` rules cover](https://code.claude.com/docs/en/permissions#what-read-and-edit-rules-cover).
- **As of:** 2026-10-29.
- **Recheck trigger:** a Claude Code release note saying a hook `if` `Edit(...)` rule matches Write
  tool calls. Re-probe before gating this row.

## What makes the numbers trustworthy

- **No figures ship; every number is measured locally.** The skill contains no token figures, tool
  inventories, or thresholds. Those drift with every CLI release. Every number in a report was
  produced by a run on the consumer's machine during that audit.
- **Every report is stamped** with the measured binary path and version, the measurement mode,
  and the session kind. Machines with two CLI installs get an answer per binary, not a blend.
- **Comparability is enforced, not advised.** `System tools` deltas are only valid between runs
  with identical skill listings (listed skill frontmatter is subtracted from that bucket); the
  engine fingerprints the listing per run and marks violating comparisons incomparable rather
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
  in `skills/audit/reference/engine.md`, relayed as of 2026-10-11; recheck this relay when that
  heading moves or its record's recheck trigger fires). When neither works, it emits a structured error with a remediation, never
  a wrong number.

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
- **As of:** 2026-10-11.
- **Recheck trigger:** that section changes when a plugin's data directory is deleted or how to
  keep it.

## Boundaries

- Usage-based removal ("which plugins do I never use") belongs to the bundled `/doctor`; the
  skill routes there and never reimplements it.
  Pointer: <https://code.claude.com/docs/en/skills#check-your-setup-with-/doctor>. As of
  2026-10-11. Recheck when that section drops unused MCP servers or plugins from its coverage.
- Which skills to turn off goes to the built-in `/skill-doctor`, which the person runs; the audit measures what a toggle saved and never picks the skill.
  Pointer: <https://code.claude.com/docs/en/skills#find-unused-skills>. As of 2026-10-02.
  Recheck when that section sends the question to another command.
- Per-skill / per-agent / per-MCP-tool attribution belongs to `/context` natively.
- This plugin answers "what is my context made of": the startup measurement and the live
  breakdown. How full the context is and what happens as it fills (zones, notices to Claude,
  toasts, optional blocking, the one-line level row) belongs to the `context-guard` plugin.
- Measurements describe **headless** sessions of the **local CLI**; interactive sessions and
  cloud/web surfaces can compose the payload differently, and reports say so.

## Configuration

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `settings_write_ask_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_SETTINGS_WRITE_ASK_ENABLED` | Runs the PreToolUse hook that asks before Write, Edit, and NotebookEdit calls aimed at a Claude Code settings file. On by default. Shell writes and files rendered into place are outside its matcher. |
| `live_display` | string | `"pane"` | `CLAUDE_PLUGIN_OPTION_LIVE_DISPLAY` | Where the live context breakdown shows. pane opens it in a pane when you run /context-budget live; band keeps it above the prompt; off shows nothing and measures nothing. /context-budget live pane, band or off changes it for the session. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure context-budget@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure context-budget@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"settings_write_ask_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install context-budget@<marketplace> -s <scope> --config settings_write_ask_enabled=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "context-budget@<marketplace>": {
         "options": {
           "settings_write_ask_enabled": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
