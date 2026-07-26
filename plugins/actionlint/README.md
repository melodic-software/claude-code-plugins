# actionlint

A Claude Code plugin that lints GitHub Actions workflow files the moment you
edit them. On every `Write` or `Edit` of a file under `.github/workflows/`
(`*.yml` or `*.yaml`) it runs [actionlint](https://github.com/rhysd/actionlint)
and surfaces any findings back to Claude as advisory context.

It ships no rules of its own and no binary — it runs the `actionlint` already on
your `PATH`.

## Behavior

- **Lint on edit.** actionlint runs on every edit of a workflow file. It is
  non-mutating; it only reports.
- **Advisory, never blocking.** The hook always exits `0`. Findings are reported
  via `additionalContext`; they never reject the edit. Make a commit hook or CI
  your hard gate.
- **Scoped to workflows.** Only files matching `.github/workflows/*.yml` and
  `.github/workflows/*.yaml` are linted. Other YAML is left alone.
- **External run-block linters disabled (`-shellcheck= -pyflakes=`).**
  actionlint's embedded-bash ShellCheck and `shell: python` pyflakes
  integrations are turned off. Each spawns a subprocess per `run:` block —
  ShellCheck deadlocks on large blocks under the Windows subprocess IPC path in
  actionlint 1.7.x, and either adds latency unsuited to an edit-time hook.
  Native workflow diagnostics are unaffected; run the full integrations in CI.
- **Graceful degrade.** When `actionlint` (or `jq`) is not on `PATH` the hook
  skips and says so — a once-per-session notice to both Claude
  (`additionalContext`) and you (`systemMessage`), never a silent no-op.

## Requirements

- **Bash** — the hook is a Bash script. On native Windows, install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  Claude Code can run it under Git Bash.
- **jq** on `PATH` — parses the hook payload. Absent: the hook skips with a
  visible once-per-session notice. [Install jq](https://jqlang.org/download/).
- **actionlint** on `PATH` — the linter itself. Absent: workflow lint skips
  with a visible once-per-session notice. See the
  [actionlint install guide](https://github.com/rhysd/actionlint/blob/main/docs/install.md).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install actionlint@melodic-software
```

Then verify prerequisites with `/actionlint:setup check`.

## Configuration

actionlint auto-discovers its own `.github/actionlint.yaml` config from your
repository when present. Two `userConfig` options tune the hook itself:

- **`actionlint_enabled`** (boolean, default `true`) — kill switch for the
  actionlint-check hook.
- **`stdin_read_timeout`** (number, default `2`, minimum `1`) — **idle** bound in
  seconds on reading the hook payload from stdin. Any byte arriving resets it, so
  a large or slowly-delivered payload is never cut off while it is still coming;
  it fires only once the pipe has gone silent for that long, and this hook then
  fails open (skips). The bound is read in four slices, so the stall is detected
  within a quarter of the configured interval of it. A producer that keeps
  emitting is bounded by Claude Code's own hook timeout, not by this value. A
  setting this shell's `read -t` will not accept — or `0` — falls back to the
  default.

Configure interactively with `/plugin configure actionlint` or headless at
install time:

```shell
claude plugin install actionlint@melodic-software --config actionlint_enabled=false
```

These options are user-scoped (stored in your user settings), so a value set
here applies across every project. To disable actionlint for a single
repository, disable the plugin in that project's `enabledPlugins` rather than
setting `actionlint_enabled`.

## License

MIT (SPDX-License-Identifier: MIT).
