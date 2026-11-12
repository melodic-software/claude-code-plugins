# bugs

A Claude Code plugin for the front of the bug lifecycle. **Read-only by default**.
It finds defects and captures them in a structured, five-field report; it does not
fix them, open a PR, or file an issue on its own.

| Skill | What it does |
|---|---|
| `/bugs:write` | Turns an informal defect description, one you already observed, into the five-field report. |
| `/bugs:scan` | Hunts for defects **nobody has observed yet** in resting code, verifies each candidate adversarially, and reports what survives. |
| `/bugs:setup` | `check` inspects both configuration files read-only; `apply` writes the tracked lane config `scan` reads. |

Invoke `/bugs:write <description>` (or let Claude reach for it
when you describe a defect). The five fields are:

1. **Title**. Present tense, one line
2. **Steps to reproduce**. Backed by the source or the reporter; never invented
3. **Expected vs actual** behavior
4. **Severity** (`low` / `medium` / `high` / `critical`) with a one-sentence justification
5. **Suggested fix location**, a file path and function/class, **no patch**

## Behavior

- **Read-only.** Emits Markdown to stdout by default. It never edits code, opens a
  PR, or files an issue unless you explicitly hand the report off.
- **Never fabricates.** Any field it cannot back from the source, a test, or the
  reporter is marked `(unknown — needs reporter confirmation)` and surfaced under
  Notes, a flagged gap, not an invented step.
- **Knows when there is no bug.** If a quick survey shows the behavior is correct,
  it emits a short "No bug confirmed" summary instead of a report.
- **Routes non-defects away.** Feature requests, investigations, and generic chores
  are recognized and pointed elsewhere rather than forced into the bug shape.

## Usage. `/bugs:write`

```text
/bugs:write [--file] [--quick|--full] [--no-survey] <bug description>
```

| Flag | Effect |
|------|--------|
| (none) | Survey the named symbol, then ask only for fields it can't back |
| `--quick` | Skip the survey when the symbol is unambiguous; at most one round of questions |
| `--full` | Always survey; up to three rounds of questions |
| `--no-survey` | Trust the description; ask only when a field would otherwise be invented |
| `--file` | Persist the report to a file (see Configuration), then offer to file it in a tracker |

## Hunting bugs nobody has reported yet

`/bugs:write` needs a defect you already noticed. `/bugs:scan` needs nothing.
No diff, no failing test, no stack trace, no comment marker. It reads resting code and
looks for what is wrong in it.

```text
/bugs:scan [<path|feature|diff>] [--lane <name>] [--track] [--dry-run] [--unattended]
```

| Flag | Effect |
|------|--------|
| (none) | Rotate: self-select the next lane from the tracked lane config, hunt it, report |
| `<path\|feature\|diff>` | Hunt exactly that scope. No rotation |
| `--lane <name>` | Hunt the named lane's globs |
| `--track` | File the verified findings as raw intake through the `work-items` plugin |
| `--dry-run` | Report to stdout only. Persists nothing, advances no rotation |
| `--unattended` | Nobody is present: run none of the scanned code, and file rather than fix |

One invocation is **one bounded pass**, which makes it usable interactively, from a loop,
or as a daily routine. Four properties matter before you rely on it:

- **Recall and precision are separated.** Per-lens hunter subagents are told to be generous;
  a separate fresh-context gate is then told to *refute* every candidate they produced. Only
  survivors reach the report, each labeled `reproduced` or `verified-by-reading`, and refuted
  candidates stay in the report with the argument that killed them.
- **Your repository's code runs only when you approve it.** Hunters and gates only read. A gate
  may propose a check, such as a test; an interactive run asks you before each one, and a run
  passed `--unattended` runs none and labels every finding `verified-by-reading`.
- **A bare run is read-only toward your repository and stays within a budget**. It stops at
  three verified findings or a complete lane sample. Filing happens only when you pass
  `--track`, and a complete lane sample is never reported as the lane being bug-free.
- **Cost follows the scope, never the precision.** Hunters and gates take their models from the
  multi-agent role map (the skill's sizing table names the roles); hunters pass no effort and gates
  always pass one, the map's verifier effort or the session's level when higher, and the
  [skill's sizing section](skills/scan/SKILL.md#sizing-model-by-stage-breadth-by-scope-effort-as-the-ceiling)
  owns what level each then runs at. A gate never runs on a weaker model than the hunters it checks,
  or below the session's effort; the scope's
  size picks how many lenses run and how many candidates reach a gate, and the session's effort
  level is the ceiling. A main-thread triage step seeds from the previous run's ungated tail, merges
  same-cause candidates, and parks cosmetic ones before any gate is spent.

Verified findings leave through one ladder: in an interactive session a local finding (one plugin,
no documented contract change, a test file to extend) is fixed in that session through the implement
lane; a non-local or security-relevant one, and every finding from an unattended run, is filed with
`--track`. Root-causing routes to `/debugging:debug`, and anything security-relevant routes to the
`review:security-review` lane. On a cloud or scheduled session, pass `--track`: the filed item is
the output the plugin relies on to outlive the session, and it is what the next rotation reads
back. When checking where the plugin data directory lives and how long it is kept, fetch
[plugins manifest reference: Environment variables](https://code.claude.com/docs/en/plugins/manifest-reference#environment-variables)
live.

## Configuration

Two surfaces with two different owners.

**Personal.** One optional `userConfig` value, owned by Claude Code:

| Option | Type | Effect |
|--------|------|--------|
| `output_dir` | directory | Where `--file` writes reports. **Leave unset** and reports go to the plugin's own persistent data directory. Set it to a path in your repository if you want bug reports committed alongside your code. |

Changes to it go through Claude Code's own plugin configuration. When checking when Claude Code
prompts for the value and where it stores it, fetch
[plugins manifest reference: User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
live.

**Team, the tracked `docs/conventions/bugs.yaml`**, which `/bugs:scan` reads for its lanes
(`lanes`), checked against
[`schemas/bugs.schema.json`](schemas/bugs.schema.json). Its filing policy (`filing_posture`) lives in
the work-items team file, `docs/conventions/work-items.yaml`; for one release `/bugs:scan` still
reads a `filing_posture` left in `docs/conventions/bugs.yaml`, with a notice to move it. A `## Gotchas` section in the prose file
beside it, `docs/conventions/bugs.md` (and in the user-global and personal override layers),
concatenates after the bundled gotchas when
`/bugs:scan` or `/bugs:write` loads. Repo-specific lines stay in the layer; a line that is not
repo-specific is filed as an issue on this marketplace (`melodic-software/claude-code-plugins`) for
curation into the shipped skill. The config is layered per the marketplace's
config-cascade convention, a user-global file, this tracked team file, and a gitignored personal
override. All layers are optional: with no config at all, `scan` rotates over bundled generic
default lanes. Keys, defaults, layer order, and per-key merge semantics live in
[`reference/config.md`](reference/config.md), their single home.

Run `/bugs:setup` to work on either surface. `check` (the default) reports both read-only:
the rendered `output_dir` and which layer supplied each lane config value. `apply` writes the
tracked file and nothing else. It drafts lane candidates from your repository, confirms them one
at a time, and never touches settings, `pluginConfigs`, the personal override, or your `.gitignore`.

Project-specific conventions, naming, areas, tracker choice, priority labels, are
read from the **consuming project's own `CLAUDE.md` / rules**; the plugin imposes
none of its own.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `output_dir` | directory | *(none)* | Where --file writes reports. When unset, reports go to the plugin's own persistent data directory. Set this to a path in your repository if you want bug reports committed alongside your code. |

### How to set these

Set the options above for `bugs@<marketplace>`, replacing `<marketplace>` with the
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

## Filing a report

`--file` persists the report; filing is an explicit, separate hand-off. When the
`work-items` plugin is installed and a tracker binding resolves, the report is handed
to `/work-items:track add`, which owns dedupe, the body template, and the argv-safe
write. Without it, in a GitHub repository with the `gh` CLI available:

```shell
gh issue create --type Bug --body-file <report-path>
```

Let `gh` prompt for the title interactively. On a repository without native Issue Types, omit
`--type Bug` and add a `type: bug` label instead. When checking what `--type` takes, fetch
[gh issue create: Options](https://cli.github.com/manual/gh_issue_create#options) live. If filing
non-interactively, never paste the reporter's title text into the command string. Write it to a file and pass
`--title "$(cat <title-file>)"`: the substitution result is a quoted argument value and
is not re-parsed, so backticks or `$( )` in reporter text cannot execute.

If a work-item tracker MCP tool is available, the skill can hand off to that instead.
Otherwise the emitted report is the deliverable. Copy it into your tracker.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install bugs@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
