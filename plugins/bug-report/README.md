# bug-report

A Claude Code plugin for the front of the bug lifecycle — **read-only by default**.
It finds defects and captures them in a structured, five-field report; it does not
fix them, open a PR, or file an issue on its own.

| Skill | What it does |
|---|---|
| `/bug-report:write` | Turns an informal defect description — one you already observed — into the five-field report. |
| `/bug-report:scan` | Hunts for defects **nobody has observed yet** in resting code, verifies each candidate adversarially, and reports what survives. |
| `/bug-report:setup` | `check` inspects both configuration surfaces read-only; `apply` writes the tracked lane config `scan` reads. |

Invoke `/bug-report:write <description>` (or let Claude reach for it
when you describe a defect). The five fields are:

1. **Title** — present tense, one line
2. **Steps to reproduce** — backed by the source or the reporter; never invented
3. **Expected vs actual** behavior
4. **Severity** (`low` / `medium` / `high` / `critical`) with a one-sentence justification
5. **Suggested fix location** — a file path and function/class, **no patch**

## Behavior

- **Read-only.** Emits Markdown to stdout by default. It never edits code, opens a
  PR, or files an issue unless you explicitly hand the report off.
- **Never fabricates.** Any field it cannot back from the source, a test, or the
  reporter is marked `(unknown — needs reporter confirmation)` and surfaced under
  Notes — a flagged gap, not an invented step.
- **Knows when there is no bug.** If a quick survey shows the behavior is correct,
  it emits a short "No bug confirmed" summary instead of a report.
- **Routes non-defects away.** Feature requests, investigations, and generic chores
  are recognized and pointed elsewhere rather than forced into the bug shape.

## Usage

```text
/bug-report:write [--file] [--quick|--full] [--no-survey] <bug description>
```

| Flag | Effect |
|------|--------|
| (none) | Survey the named symbol, then ask only for fields it can't back |
| `--quick` | Skip the survey when the symbol is unambiguous; at most one round of questions |
| `--full` | Always survey; up to three rounds of questions |
| `--no-survey` | Trust the description; ask only when a field would otherwise be invented |
| `--file` | Persist the report to a file (see Configuration), then offer to file it in a tracker |

## Hunting bugs nobody has reported yet

`/bug-report:write` needs a defect you already noticed. `/bug-report:scan` needs nothing —
no diff, no failing test, no stack trace, no comment marker. It reads resting code and
looks for what is wrong in it.

```text
/bug-report:scan [<path|feature|diff>] [--lane <name>] [--track] [--dry-run]
```

| Flag | Effect |
|------|--------|
| (none) | Rotate: self-select the next lane from the tracked lane config, hunt it, report |
| `<path\|feature\|diff>` | Hunt exactly that scope — no rotation |
| `--lane <name>` | Hunt the named lane's globs |
| `--track` | File the verified findings as raw intake through the `work-items` seam |
| `--dry-run` | Report to stdout only — persists nothing, advances no rotation |

One invocation is **one bounded pass**, which makes it usable interactively, from a loop,
or as a daily routine. Two properties are worth knowing before you rely on it:

- **Recall and precision are separated.** Per-lens hunter subagents are told to be generous;
  a separate fresh-context gate is then told to *refute* every candidate they produced. Only
  survivors reach the report, each labeled `reproduced` or `verified-by-reading`, and refuted
  candidates stay in the report with the argument that killed them.
- **A bare run is read-only toward your repository and stays within a budget** — it stops at
  three verified findings or a complete lane sample. Filing happens only when you pass
  `--track`, and a complete lane sample is never reported as the lane being bug-free.

Verified findings are handed off, not fixed here: root-causing routes to `/debugging:debug`,
and anything security-relevant routes to the `review:security-review` lane.

## Configuration

Two surfaces with two different owners.

**Personal — one optional `userConfig` value**, prompted by Claude Code at enable time:

| Option | Type | Effect |
|--------|------|--------|
| `output_dir` | directory | Where `--file` writes reports. **Leave unset** and reports go to the plugin's own persistent data directory. Set it to a path in your repository if you want bug reports committed alongside your code. |

Claude Code owns this value: current releases ignore plugin `userConfig` values placed in
project or local settings, and changes route through Claude Code's own configuration prompt.

**Team — the tracked `.claude/bug-report.md`**, which `/bug-report:scan` reads for its lanes
(`lanes`) and its filing policy (`filing_posture`). It is layered per the marketplace's
config-cascade convention — a user-global file, this tracked team file, and a gitignored local
overlay. All layers are optional: with no config at all, `scan` rotates over bundled generic
default lanes. Keys, defaults, layer order, and per-key merge semantics live in
[`reference/config.md`](reference/config.md), their single home.

Run `/bug-report:setup` to work on either surface. `check` (the default) reports both read-only:
the rendered `output_dir` and which layer supplied each lane config value. `apply` writes the
tracked file and nothing else — it drafts lane candidates from your repository, confirms them one
at a time, and never touches settings, `pluginConfigs`, the local overlay, or your `.gitignore`.

Project-specific conventions — naming, areas, tracker choice, priority labels — are
read from the **consuming project's own `CLAUDE.md` / rules**; the plugin imposes
none of its own.

## Filing a report

`--file` persists the report; filing is an explicit, separate hand-off. In a GitHub
repository with the `gh` CLI available:

```shell
gh issue create --type Bug --body-file <report-path>
```

Let `gh` prompt for the title interactively. `--type Bug` sets the native GitHub Issue
Type (org repos; omit on repos without native Issue Types, adding a `type: bug` label instead). If filing non-interactively, never paste
the reporter's title text into the command string — write it to a file and pass
`--title "$(cat <title-file>)"`: the substitution result is a quoted argument value and
is not re-parsed, so backticks or `$( )` in reporter text cannot execute.

If a work-item tracker MCP tool is available, the skill can hand off to that instead.
Otherwise the emitted report is the deliverable — copy it into your tracker.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bug-report@<marketplace>
```

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `output_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_OUTPUT_DIR` | Where --file writes reports. When unset, reports go to the plugin's own persistent data directory. Set this to a path in your repository if you want bug reports committed alongside your code. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure bug-report@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install bug-report@<marketplace> -s <scope> --config output_dir=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "bug-report@<marketplace>": {
         "options": {
           "output_dir": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
