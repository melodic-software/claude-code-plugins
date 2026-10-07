# context-budget

Measure a Claude Code session's fixed startup context payload **per item**, on your machine, at a
pinned binary, and record what every trim actually saved.

`/context` already itemizes skills, agents, and MCP tools. What it structurally cannot itemize is
the built-in tool pool: `System tools` and `System tools (deferred)` are lump sums, and together
they are typically the largest single contributor to the fixed payload. This plugin attributes
them per tool by A/B differencing: a baseline headless session versus one session per candidate
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

## Hook

A PreToolUse checkpoint returns `permissionDecision: "ask"` when a **file-editing tool call**
(`Write`, `Edit`, `NotebookEdit`) targets a Claude Code settings file, so those
edits prompt even in auto mode. The files it matches are `settings.json` and `settings.local.json`
under any `.claude` directory (project or user-global), plus `managed-settings.json`. It is a
checkpoint, not a guarantee (a `PermissionRequest` hook can allow the call; `disableAllHooks`
removes non-managed hooks). Kill switch: the `settings_write_ask_enabled` plugin option.

An installed mod can stop this plugin's `PreToolUse` hooks from running: they run after the last
mod calls `next`, so a mod that answers a `tool.call` without calling it skips them
([where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)).
A mod can also approve a call they blocked, because its `tool.check` hook runs after them
([approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).

**What it does not see.** The checkpoint matches tool names and file paths, not the file on
disk. These routes change a settings file without an ask:

- A write through the shell: a redirect, a heredoc, `sed -i`, `cp`, `tee`, or a script run by
  `Bash` or `PowerShell`. None of them passes through a file-editing tool.
- A tool that renders configuration into place from a source elsewhere, such as a dotfile manager
  applying a template or symlink. That write is a legitimate action by another program, inside the
  session or outside it.
- A drop-in under `managed-settings.d/`, which the path match does not include.

For a signal that fires whatever wrote the file, Claude Code's `ConfigChange` hook event runs
when a settings file changes during a session. It can stop the new settings from applying to the
running session (except for `policy_settings`), but it cannot ask, it discards `systemMessage`,
a blocked change surfaces no message, and the file on disk has already changed. That is a
different control from this one, and this plugin does not register it.
Verified 2026-09-29 against Claude Code 2.1.284 at <https://code.claude.com/docs/en/hooks>
("ConfigChange" and "FileChanged", and the matcher table that filters PreToolUse on
`tool_name`). Recheck when that page gives `ConfigChange` an `ask` outcome or a visible message,
or gives PreToolUse a matcher on target path.

**Decision (#3864): the claim is narrowed, and the hook is not widened.** Adding the shell lane
would put an always-on `Bash|PowerShell` hook under the
[hook-budget](../../docs/conventions/hook-budget/README.md) ceiling on every shell call in every
consumer. It would recognize a settings write only by guessing from the command string, and it
would still miss the render-into-place route. So even after paying that cost, the checkpoint could
not honestly claim every settings write. The `/context-budget:audit fix` path edits project
settings through a file-editing tool, so the checkpoint does cover this plugin's own write path.
Treat a future audit that finds this gap as re-filing it, not as a new defect.

The registration carries no `if` filter, so the hook process spawns on every matched write and the
script decides. An `if` gate was evaluated for this row on 2026-09-02 and rejected. On Windows,
Claude Code's `if` file rules do not match an absolute path outside the working directory under any
anchoring form tested, including the home-relative `~/`, the root-anchored `//`, the drive-letter
spelling, and the root-anchored recursive glob. A probe session logged every candidate rule as
skipped on a write to the user-global settings file and on a write to the managed-settings file,
while the unconditioned row fired and returned `ask` for both. Only a settings file inside the
working directory matched. Any gate on this row would therefore drop the user-global and
managed-settings checks silently, which is the opposite of what the checkpoint exists to do. The row
stays unconditioned until upstream matching reaches those paths.

## What makes the numbers trustworthy

- **Nothing is shipped, everything is measured.** The skill contains no token figures, tool
  inventories, or thresholds. Those drift with every CLI release. Every number in a report was
  produced by a run on the consumer's machine during that audit.
- **Every report is stamped** with the measured binary path and version, the measurement mode,
  and the session kind. Machines with two CLI installs get an answer per binary, not a blend.
- **Comparability is enforced, not advised.** `System tools` deltas are only valid between runs
  with identical skill listings (listed skill frontmatter is subtracted from that bucket); the
  engine fingerprints the listing per run and marks violating comparisons incomparable rather
  than reporting their numbers.
- **Levers are catalogued data, not folklore.** Each row in
  `skills/audit/reference/levers.json` carries its honesty category (does it remove weight, work
  but save nothing here, block without saving, sit as vendor weight, or cost more than it buys),
  the official citation behind it, how to detect and measure it, the exact config it would emit,
  and a recheck trigger. A lever whose category cannot be determined for your configuration is
  not offered.
- **Honest degradation.** Exact mode uses the Agent SDK's structured context usage. Without the
  SDK, the engine parses headless `/context` output version-aware (display-rounded, and flagged
  as resting on an undocumented surface). When neither works, it emits a structured error with a
  remediation, never a wrong number.

## Prerequisites

- `node` (required, the engine's runtime).
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
- Which skills to turn off goes to the built-in `/skill-doctor`, which the person runs; the audit measures what a toggle saved and never picks the skill.
  Pointer: <https://code.claude.com/docs/en/skills#find-unused-skills>. As of 2026-10-02.
  Recheck when that section sends the question to another command.
- Per-skill / per-agent / per-MCP-tool attribution belongs to `/context` natively.
- Live in-session occupancy zones belong to the `context-guard` plugin.
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

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure context-budget@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install context-budget@<marketplace> -s <scope> --config settings_write_ask_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

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

   Plugin option values are read from **user** and managed settings only, **not**
   from a project's `.claude/settings.json`. To vary behavior per repository,
   enable or disable the plugin in that project's `enabledPlugins` instead of
   setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
