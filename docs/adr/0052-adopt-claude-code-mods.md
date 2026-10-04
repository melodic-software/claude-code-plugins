# Adopt Claude Code mods

- Status: accepted
- Date: 2026-10-03
- Supersedes: [ADR 0035](0035-defer-claude-code-mods-with-five-go-criteria.md)

This record was to stay Proposed until a probe on a machine with a Team or Enterprise sign-in
passed. The owner ruled that machine out of scope on 2026-10-03, so the record is Accepted without
it: how the guard mods behave under the built-in guard `sec-default` rests on the upstream docs and
the design, not on a probe ([Where the guard mods run](#where-the-guard-mods-run)).

## Context

[ADR 0035](0035-defer-claude-code-mods-with-five-go-criteria.md) deferred mods on 2026-09-19 at
Claude Code 2.1.278, when all five of its go criteria failed. By 2.1.288 the official docs carry ten
pages under `docs/en/plugins/mods/`, mods are on by default from 2.1.287, and the 2.1.288 changelog
lists a fix matching the description of
[anthropics/claude-code#92533](https://github.com/anthropics/claude-code/issues/92533).
The criteria were re-run on 2026-10-02 at 2.1.288; the commands and output are in
[go-no-go.md](../upstream/claude-code-mods/go-no-go.md#run-record-2026-10-02-claude-code-21288).
Criteria 1, 2 and 4 hold. Criterion 3 fails as written (#92533 is open, and the probe in
[E8](../upstream/claude-code-mods/experiments.md#e8-92533-three-arm-probe-2026-10-02) did not
reproduce it on Linux). Criterion 5 fails as written: the early-access line is still in the upstream
`mods/README.md` and in the header of the per-build types, and no docs page carries one.

Every fact about mods here rests on Anthropic as the single publisher (the docs pages, the per-build
types, the changelog), plus this repository's own probes. None is independently confirmed.

Two plugins in this marketplace, context-guard and rate-limit-guard, worked around missing native
surfaces: a status-line tee wrote files that settings hooks read and injected back as context.
A mod does those jobs in-process (session events, context lines added to a tool result, a band in
the interface, a tool Claude can call), which is the gap this record answers.

## Decision

**Adopt mods, with no policy narrowing of what a mod may do.** A plugin in this marketplace may ship
a mod and use any capability the docs give one, `tool.check` included. That carries a consequence,
acknowledged and accepted. The built-in guard `sec-default` loads only on a machine with managed
settings or for a user signed in with a Team or Enterprise plan, and where it loads a user's mod
can't approve a call that a `deny` rule refuses, unless an administrator sets
`allowModsToOverrideDenyRules`. Where the guard does not load, as on the owner's Max machines with
no managed settings, any installed mod's `tool.check` hook can approve a call a `deny` rule
refuses, and in auto mode a call a mod approves runs without a classifier check, in lanes that hold
push credentials. This repository's own guard mods use no `tool.check`. Basis:
[admin: know what happens by default](https://code.claude.com/docs/en/plugins/mods/admin#know-what-happens-by-default)
and [admin: know which controls still apply](https://code.claude.com/docs/en/plugins/mods/admin#know-which-controls-still-apply),
as of 2026-10-03, Claude Code 2.1.288.

### Choosing a mod

- **New work.** Choose by upstream's comparison of mods, settings hooks, skills and MCP servers
  ([overview: compare](https://code.claude.com/docs/en/plugins/mods/overview#compare-mods-settings-hooks-skills-and-mcp-servers)).
  Prefer a mod where it does natively what a plugin would otherwise do through a workaround: a
  status-line tee, or a settings hook that reads a file another script wrote and injects it.
- **Converting an existing plugin.** Convert only when the mod matches every behavior of what it
  replaces, where mods can load: every behavior an operator, Claude, a file reader or a loop lane
  observes, plus the plugin's contract rules, except differences the owner accepts by name. Tests of
  retired parts retire with them, and any responsiveness or process-cost property they guarded is
  replaced by the mod's own budget. A plugin whose mod cannot match it stays as it is and is
  improved later.

### Packaging and loading

- **One mod per plugin**, living in the plugin whose feature it serves, beside that feature's
  skills and commands. The engine loads one hooks module per plugin, and a plugin's switch in
  `/plugin` is the switch for its mod. A feature that must switch off independently is its own
  plugin. Default state is the plugin's `defaultEnabled` in its marketplace entry.
- **Optional features inside a mod** each get a `userConfig` option with a default; an interface
  feature also gets a show/hide command.
- **Settings hooks stay where they must run with mods off**, in the same plugin's `hooks.json`
  beside the mod. Where no native mod equivalent exists, the hook stays a settings hook rather than
  blocking the conversion.
- **One implementation of a behavior at a time.** A behavior that moves into a mod is removed from
  its settings hook or script in the same change; nothing keeps both running as a fallback.
- **Version floor 2.1.287.** A mod-bearing plugin declares it and supports nothing older: no
  shims, stubs or compatibility paths for older builds.
- **Generated files.** Commit the one-line root `tsconfig.json` Claude Code writes beside a mod.
  Never commit `.claude-plugin/types/`; it carries its own `.gitignore`.
- **Development** happens in the plugin's own directory, loaded with `--plugin-dir` in the CLI or
  `CLAUDE_CODE_PLUGIN_DIRS` in apps that take no flag, the Desktop app among them.

### Where the guard mods run

On a machine with managed settings, or for a user signed in with a Team or Enterprise plan, Claude
Code loads the built-in guard `sec-default` ahead of every user mod. On some events it continues
past the user tier, so a user mod's hooks there do not run: `classic.*`, `prompt.section`,
`prompt.context`, `prompt.compose` and others its rows name. The guard mods hook none of them. Every
event they hook and every `$` call they make sits in a row the guard passes, with one conditional:

| Hook or `$` call | Used by | The guard's row |
| --- | --- | --- |
| `session.start`, `session.end`, `session.compact`, `session.measure` | both | passes (`session.*`) |
| `turn.start`, `turn.complete`; `turn.step` | both; rate-limit-guard | passes (`turn.*`) |
| `prompt.submit`, `tool.call`, `command.run`, `ui.render` | both | passes |
| `$.process.run`, `$.clock.*`, `$.fs.read`, `$.fs.stat`, `$.ui.log`, `$.ui.toast`, `$.ui.invalidate`, `$.ui.resolve`, `$.command.register` | both | passes (`process.run`, `clock.*`, `fs.*`, `ui.*`, `command.register`) |
| `$.fs.exists` | context-guard | passes (`fs.*`) |
| `$.session.*`, `$.env.get`, `$.plugin.*`, `$.prompt.read`, `$.prompt.suggest` | both | passes (no row holds them) |
| `$.tool.list` | context-guard | passes; the organization's managed MCP tools are listed as its tiers listed them |
| `$.tool.register` | both | refused for a user mod while managed settings hold `allowedMcpServers` |

A refused tool registration is logged once and the guard carries on without its status tool; its
lines, band and contract file do not depend on it. Organization-admin features are out of scope.

- **Pointer**: for which events and calls the guard holds and which pass, see "The rows" in
  [`mods/sec-default/README.md`](https://github.com/anthropics/claude-code/blob/main/mods/sec-default/README.md#the-rows);
  for when it loads, see
  [admin: know what happens by default](https://code.claude.com/docs/en/plugins/mods/admin#know-what-happens-by-default).
  The hooks and calls in the table are those in `plugins/context-guard/hooks/register.tsx` and
  `plugins/rate-limit-guard/hooks/register.tsx`.
- **As of**: 2026-10-03, Claude Code 2.1.288
- **Recheck trigger**: "The rows" moves any hook or call in the table into a row the guard holds,
  or changes when it refuses `tool.register`; or either guard's module starts hooking an event or
  calling a `$` method the table does not list.

### Conventions and review

- The [mod-authoring convention](../conventions/mod-authoring/README.md) points at the upstream
  pages and restates none of their tables. It keeps only facts upstream does not state, each with
  tracked evidence.
- No mod-authoring skill: the built-in `plugin-authoring` skill owns authoring and is regenerated
  for each build.
- No CI check or other enforcement for mods until a concrete need appears. Review applies the
  convention.
- Stability is judged on the docs pages and on the header of the per-build types, rechecked on
  every pin bump by the replaced criterion 5 in
  [go-no-go.md](../upstream/claude-code-mods/go-no-go.md#criterion-5-as-replaced). The wording of
  the upstream `mods/README.md` no longer gates.

## Alternatives considered

- **Keep deferring until all five criteria pass as written.** Rejected: criterion 5 reads a README
  in the source tree while the docs pages users are pointed at carry no warning, and criterion 3
  waits on an issue whose Bash half did not reproduce at 2.1.288.
- **Adopt within local scope rules** (each mod its own plugin, no unfiltered `tool.call`, guards
  kept as settings hooks, no network calls). Rejected by the owner: each rule narrows what the docs
  let a mod do by local policy, and the guard rule kept the status-line workaround this record
  exists to retire.
- **Keep each guard's settings hook as a fallback beside its mod.** Rejected: two implementations of
  one behavior run at once and can disagree; where mods cannot load, the guards run reactive-only
  and their setup check says mods are off.
- **Write a mod-authoring skill.** Rejected: `plugin-authoring` owns authoring, and `plugin-quality`,
  `harness-config` and `harness-ops` already cover audit, settings and inventory.

## Consequences

- context-guard and rate-limit-guard each run as a mod that replaced its status-line tee, shim,
  status-line wiring and the hooks the mod does natively, each after its parity inventory passed.
  context-guard's zone gate moved into its mod; the post-compaction marker and the rate-limit stop
  recorder stay settings hooks.
- One crashing mod does not take the guards down with it. A crash Claude Code traces to one mod
  unloads that mod alone; only crashes it cannot trace to one mod count toward the limit that
  unloads every installed mod for the session. In this repository's close-out probe a test mod
  that blocked the hooks worker was unloaded, and both guard mods stayed loaded and kept writing.
  Basis:
  [troubleshoot: it crashed the hooks worker](https://code.claude.com/docs/en/plugins/mods/troubleshoot#it-crashed-the-hooks-worker)
  and
  [mods that run in the hooks worker are off for this session](https://code.claude.com/docs/en/plugins/mods/troubleshoot#mods-that-run-in-the-hooks-worker-are-off-for-this-session),
  as of 2026-10-03, Claude Code 2.1.288.
- A mod that answers a tool call without calling `next` keeps plugin `PreToolUse` settings hooks
  from running, and a `tool.check` hook can approve a call they blocked
  ([events: where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order);
  [events: approve or refuse a tool call](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked)).
  The README of each plugin with `PreToolUse` hooks says so.
- Where mods cannot load, what still runs depends on the case; upstream lists the cases in
  [overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off),
  [overview: where mods run](https://code.claude.com/docs/en/plugins/mods/overview#where-mods-run),
  [admin: know which controls still apply](https://code.claude.com/docs/en/plugins/mods/admin#know-which-controls-still-apply),
  [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load)
  and [troubleshoot: refusal messages](https://code.claude.com/docs/en/plugins/mods/troubleshoot#refusal-messages).
  These cases apply to a plugin that managed settings do not force-enable in `enabledPlugins`.
  Where mods are off and settings hooks still run, as under an organization's
  `allowManagedModsOnly`, a converted plugin keeps only its settings hooks. Where hooks or plugins
  are off altogether, neither runs: `disableAllHooks` in a user's own settings, `--safe-mode`,
  `--bare`, `allowManagedHooksOnly`, and a Desktop session in WSL. Below 2.1.287 nothing is
  supported. A plugin managed settings force-enable keeps its settings hooks under
  `disableAllHooks` outside managed settings and under `allowManagedHooksOnly`, but its mod loads
  there, and under `allowManagedModsOnly`, only when it counts as the organization's, which a
  plugin Claude Code copies into its cache from a GitHub source, as this marketplace's are, does
  not. Basis:
  [settings reference: `disableAllHooks`](https://code.claude.com/docs/en/settings-reference#disableallhooks),
  [what runs under `allowManagedHooksOnly`](https://code.claude.com/docs/en/settings-reference#what-runs-under-allowmanagedhooksonly),
  [admin: install your organization's mods](https://code.claude.com/docs/en/plugins/mods/admin#install-your-organizations-mods).
- `scripts/test-plugin-mods.sh` runs `claude plugin test` on every plugin whose `hooks.json` names
  `modules`, and skips when the `claude` on `PATH` predates `claude plugin test`.

## Recheck triggers

Every pointer above is as of 2026-10-03, Claude Code 2.1.288. Re-derive this record when:

- a pull request bumps the `@anthropic-ai/claude-code` pin in `package.json`: run the quick check in
  [go-no-go.md](../upstream/claude-code-mods/go-no-go.md#quick-check-for-a-claude-code-pin-bump);
- a docs page under `docs/en/plugins/mods/` adds an early-access or "without notice" warning;
- `sec-default` starts holding a hook or `$` call either guard mod uses (the table under
  [Where the guard mods run](#where-the-guard-mods-run)), or a guard mod starts using one the table
  does not list;
- #92533 changes state.

## Links

The evidence trail, the runbook and the cited source index live in
[docs/upstream/claude-code-mods/](../upstream/claude-code-mods/). The authoring pointers are in
[docs/conventions/mod-authoring/](../conventions/mod-authoring/README.md).
