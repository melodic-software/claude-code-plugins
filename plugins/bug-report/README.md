# bug-report

A Claude Code plugin that turns an informal defect description into a structured,
five-field bug report — **read-only by default**. It captures; it does not fix,
open a PR, or file an issue on its own.

Invoke it with `/bug-report:write <description>` (or let Claude reach for it
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

## Configuration

One optional personal `userConfig` value, prompted by Claude Code at enable time:

| Option | Type | Effect |
|--------|------|--------|
| `output_dir` | directory | Where `--file` writes reports. **Leave unset** and reports go to the plugin's own persistent data directory. Set it to a path in your repository if you want bug reports committed alongside your code. |

Run `/bug-report:setup` to validate this choice interactively. It reads the rendered option,
recommends the uncommitted default, and routes changes through Claude Code's plugin configuration
prompt. Current releases ignore plugin `userConfig` values placed in project or local settings.

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
/plugin install bug-report@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
