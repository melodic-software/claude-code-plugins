# Adopt Claude Code mods within five scope rules

- Status: accepted
- Date: 2026-10-02
- Supersedes: [ADR 0035](0035-defer-claude-code-mods-with-five-go-criteria.md)

## Context

[ADR 0035](0035-defer-claude-code-mods-with-five-go-criteria.md) deferred mods on 2026-09-19 at
Claude Code 2.1.278, when all five of its go criteria failed. By 2.1.288 the surface had changed:
the official docs carry ten pages under `docs/en/plugins/mods/`, mods are on by default from 2.1.287,
and the 2.1.288 changelog lists a fix for the defect behind
[anthropics/claude-code#92533](https://github.com/anthropics/claude-code/issues/92533).

The five criteria were re-run on 2026-10-02 at Claude Code 2.1.288. The commands and their output
are in [go-no-go.md](../upstream/claude-code-mods/go-no-go.md#run-record-2026-10-02-claude-code-21288).

1. **A test mod loads with `CLAUDE_CODE_ENABLE_FUNCTION_HOOKS` unset: holds.** A probe mod loaded
   in a `-p` run and in an interactive session with the variable unset, and 2.1.287 and later
   ignore the variable.
2. **The official docs mention the feature: holds.** The docs index lists ten mods pages.
3. **#92533 is closed: fails as written.** The issue is still open. The 2.1.288 changelog lists a
   fix, and a three-arm probe on Linux found no failure with no plugin, with a `tool.call` hook
   filtered to the mod's own tool, or with a passthrough Bash hook. The file-search half of
   the 2.1.288 fix is untested, Windows was not re-run, and a commenter on the issue reports
   `$.session.cwd()` returning the parent directory inside a worktree subagent.
4. **The docs state throw and timeout semantics and the default: holds.**
5. **The early-access warning is gone from `mods/README.md`: fails as written.** The README and the
   header of the 2.1.288 types still carry it. None of the ten docs pages carries an early-access
   or "without notice" warning.

## Decision

**Adopt mods, scoped.** A plugin in this marketplace may ship a mod that follows the five rules
below. Criteria 3 and 5 no longer hold the verdict: rule 2 keeps every mod here out of the hook
shape #92533 reports, and criterion 5 is replaced below. Mods fill gaps settings hooks cannot
fill (drawing, commands, tools Claude can call, in-process session state). ADR 0035 stopped at
the Native-first gate's second test on Anthropic's own instability warning and missing docs; the
docs now cover the surface, and criterion 5's replacement says how stability is judged from here.

### Scope rules

1. **R1: each mod ships as its own plugin.** A mod is never added to an existing plugin. The way
   to turn one mod off is to disable or uninstall its plugin, so a mod inside a plugin that carries
   settings hooks would take those hooks down with it.
   Basis: [overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off).
2. **R2: no unfiltered `tool.call` hook, and no `tool.call` hook on Bash, PowerShell or any other
   tool that runs shell commands.** An unfiltered hook sees shell calls too, so it falls under the
   same ban. A `tool.call` hook filtered to a tool the mod registers itself with `$.tool.register`,
   named `mcp__<plugin>__<name>`, is allowed, because that hook is how a registered tool is
   answered. Basis: [api: add a tool](https://code.claude.com/docs/en/plugins/mods/api#add-a-tool);
   the `$.tool.register` declaration in the 2.1.288 `plugin-authoring` types;
   [#92533](https://github.com/anthropics/claude-code/issues/92533); arm B of
   [E8](../upstream/claude-code-mods/experiments.md#e8-92533-three-arm-probe-2026-10-02).
3. **R3: every hook carries a `.catch` handler, and a hook that guards anything fails closed in
   it.** Without one, a hook that throws, times out or returns the wrong shape is skipped and the
   event goes on, so a guard without one lets the guarded action run.
   Basis: [events: handle a hook that fails](https://code.claude.com/docs/en/plugins/mods/events#handle-a-hook-that-fails);
   [reference: the hook function](https://code.claude.com/docs/en/plugins/mods/reference#the-hook-function).
4. **R4: guards stay settings hooks.** A mod never answers or rewrites a `tool.call` for a tool it
   does not own. Plugin `PreToolUse` settings hooks run after the last mod calls `next`, so a mod
   that answers first keeps this repository's guard hooks from running. ADR 0035's three
   conditions for converting guard hooks to mods are dropped with it: guards are not converted.
   Basis: [events: where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order).
5. **R5: no session data leaves the machine.** A mod in this repository makes no `$.http` call
   and sends no session content off the machine, unless an exception is reviewed and recorded as
   an amendment to this record, naming the endpoint and the data sent. A `prompt.context` hook
   receives every instruction file, the user's private global `CLAUDE.md` included.
   Basis: ADR 0035's data-exposure consequence, observed 2026-09-19 at 2.1.278, and
   [E5](../upstream/claude-code-mods/experiments.md#e5-what-a-mods-handler-receives);
   [overview: what a mod can reach](https://code.claude.com/docs/en/plugins/mods/overview#what-a-mod-can-reach).

### Criterion 5, replaced

Stability is judged on the ten docs pages and on the header of the `plugin-authoring` types for
the build in use, rechecked on every pin bump. The wording of `mods/README.md` no longer gates. At
adoption the docs pages carry no early-access warning and the 2.1.288 types header does; adoption
accepts the header as it stands, and each recheck records whether it changed.

### Where mods run

- A Desktop session in WSL loads no plugins, so no mod runs there.
- `claude -p`, the Agent SDK, the VS Code extension's chat panel, and cloud sessions the plugin
  reaches run a mod's hooks and show nothing it draws, so a mod whose value is what it draws does
  nothing in an unattended lane.
- The where-mods-run section does not mention `--bg` sessions, and none has been probed here.
- Desktop takes no `--plugin-dir`. To load a plugin directory without installing it, Desktop reads
  `CLAUDE_CODE_PLUGIN_DIRS` from its environment or from the `env` block of
  `~/.claude/settings.json`. Desktop was not probed in the 2026-10-02 re-run.

Basis: [overview: where mods run](https://code.claude.com/docs/en/plugins/mods/overview#where-mods-run);
[reference: settings and environment variables](https://code.claude.com/docs/en/plugins/mods/reference#settings-and-environment-variables);
the 2.1.288 `plugin-authoring` skill's `reference.md` (line 68) names the Desktop app as an app that
takes no `--plugin-dir`.

## Alternatives considered

- **Keep deferring until all five criteria pass as written.** Rejected: criterion 5 reads a README
  in the mods source tree while the docs pages, the surface users are pointed at, carry no warning,
  and criterion 3 waits on an issue whose reported hook shape rule 2 already excludes.
- **Adopt without scope rules.** Rejected: a mod runs in-process without a sandbox, reads every
  prompt and instruction file, and can keep settings hooks from running. This repository's guard
  plugins depend on those hooks running.
- **Convert the guard hooks to mods.** Rejected by rule 4.
- **Write a mod-authoring skill.** Rejected: the built-in `plugin-authoring` skill owns authoring
  and is regenerated for each build, and `plugin-quality`, `harness-config` and `harness-ops`
  already cover audit, settings and inventory.

## Consequences

- No mod ships in this change. The first is the `usage-band` pilot
  ([#5777](https://github.com/melodic-software/claude-code-plugins/issues/5777)), in its own pull
  request, under these rules.
- [docs/conventions/mod-authoring/](../conventions/mod-authoring/README.md) points at these rules
  rather than restating them, and `.claude/rules/mod-authoring.md` loads it when a plugin's
  `hooks/` is read.
- The rules are enforced by review. This change adds no check script, and
  `scripts/check-hook-exec-form.sh` still passes a mod-shaped `hooks.json` without inspecting it,
  as ADR 0035 recorded.
- The pin is 2.1.288, so CI runs the first mod's tests; `scripts/test-plugin-mods.sh` still skips a
  CLI older than 2.1.287.
- Rule 4 names `tool.call` only. A `tool.check` hook can approve a call that a plugin `PreToolUse`
  hook blocked
  ([events: approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).
  These rules do not cover it, so a mod that hooks `tool.check` needs its own decision first.
- A mod still takes no per-repository configuration: its options are read from user or managed
  settings, never a project's, as ADR 0035 recorded.

## Recheck triggers

Every pointer above is as of 2026-10-02, Claude Code 2.1.288. Re-derive this record when:

- a pull request bumps the `@anthropic-ai/claude-code` pin in `package.json`: run the quick check in
  [go-no-go.md](../upstream/claude-code-mods/go-no-go.md#quick-check-for-a-claude-code-pin-bump),
  including the replaced criterion 5;
- a docs page under `docs/en/plugins/mods/` adds an early-access or "without notice" warning;
- #92533 changes state, or the `$.session.cwd()` report on it gets a staff reply, a changelog fix,
  or an issue of its own.

## Links

The evidence trail, the runbook with this record's run, and the cited source index live in
[docs/upstream/claude-code-mods/](../upstream/claude-code-mods/). The authoring how-to is
[docs/conventions/mod-authoring/](../conventions/mod-authoring/README.md).
