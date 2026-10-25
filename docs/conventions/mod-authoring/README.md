# Mod authoring: writing a hooks module in a marketplace plugin

Owner doc for **how a plugin in this marketplace ships a mod**: a hooks module of function hooks
that Claude Code calls in its own process. Anthropic owns the mods API and its docs; this doc points
at them and keeps only the facts about this repository, or found by its probes, that they do not
state. [ADR 0052](../../adr/0052-adopt-claude-code-mods.md) records the decisions: when to choose a
mod, one mod per plugin, the 2.1.287 floor, and what is committed.

## Boundary

- **The API itself** (events, `$` methods, render sites, limits): the built-in `plugin-authoring`
  skill and the upstream pages below. This doc restates none of it.
- **How a mod's display looks** (which surface carries which message, rows, width, color,
  wording, the off switch): `/user-interface:design`, whose mod guidance builds on its terminal
  guidance (`NO_COLOR`, non-TTY output, plain-text fallbacks).
- **Settings hooks** (`hooks` in `hooks.json`): the `hook-*` conventions, starting with
  [hook-budget](../hook-budget/README.md).
- **Three `hook-*` conventions also bind a mod**: what it tells Claude, by the frequency and
  phrasing rules of [hook-observability](../hook-observability/README.md#text-a-hook-adds-for-the-model-frequency-and-phrasing);
  its telemetry, as [hook-telemetry](../hook-telemetry/README.md) envelopes; and its process cost,
  under [hook-budget](../hook-budget/README.md#mods-a-third-enforcement-form). Each records where a
  mod differs: the guard mods' lines and telemetry are a recorded exception in hook-observability,
  and a mod's budget is enforced by `claude plugin test` counts rather than strace.
- **Terms**: this doc uses the mods pages' words, "hook" for a mod's function and "settings
  hook" for the kind a settings file or `hooks.json` runs; see the note under the title of the
  [overview](https://code.claude.com/docs/en/plugins/mods/overview).
- **Record shape** for each pointer below: [upstream-drift](../upstream-drift/README.md).

## Before writing or changing a mod

1. Load the built-in `plugin-authoring` skill. Claude Code regenerates it for each build, so it
   describes the build you run.
2. Read the upstream pages for the parts you touch, raw markdown at the page URL plus `.md`:
   [overview](https://code.claude.com/docs/en/plugins/mods/overview),
   [create](https://code.claude.com/docs/en/plugins/mods/create),
   [events](https://code.claude.com/docs/en/plugins/mods/events),
   [interface](https://code.claude.com/docs/en/plugins/mods/interface),
   [api](https://code.claude.com/docs/en/plugins/mods/api),
   [reference](https://code.claude.com/docs/en/plugins/mods/reference),
   [test](https://code.claude.com/docs/en/plugins/mods/test),
   [admin](https://code.claude.com/docs/en/plugins/mods/admin),
   [troubleshoot](https://code.claude.com/docs/en/plugins/mods/troubleshoot),
   [gallery](https://code.claude.com/docs/en/plugins/mods/gallery).
3. Run `claude plugin validate` on the plugin; its `hooks:` and `calls:` lines show what the module
   hooks and which `$` methods it calls.
4. A mod Claude writes in the session's dev-mods folder hot-reloads after the enable prompt; see
   [create: ask Claude for a mod](https://code.claude.com/docs/en/plugins/mods/create#ask-claude-for-a-mod).
5. To change an existing mod, start Claude with `--plugin-dir` on the mod's directory so edits
   reload in the same session; see
   [create: change a mod with Claude](https://code.claude.com/docs/en/plugins/mods/create#change-a-mod-with-claude).

- **Pointer**: for which source wins when a page and the per-build types disagree, see
  [create: get the types for your build](https://code.claude.com/docs/en/plugins/mods/create#get-the-types-for-your-build);
  for the `hooks:` and `calls:` lines, see
  [create: check what Claude Code reads from your mod](https://code.claude.com/docs/en/plugins/mods/create#check-what-claude-code-reads-from-your-mod).
- **As of**: 2026-10-04, Claude Code 2.1.289
- **Recheck trigger**: a linked create section moves, hot reload changes, or
  `claude plugin validate` stops listing hooks and calls.

Read Anthropic's maintained mods for working examples before writing your own; licensing and reuse
terms are recorded in [docs/upstream/claude-code-mods/sources.md](../../upstream/claude-code-mods/sources.md).

- **Pointer**: for sample mods, see the
  [playground `claude-code/mods`](https://github.com/anthropics/claude-code-playground/tree/569c5283d9a0a7ee7938df85bb32e4f48cbb8c86/claude-code/mods)
  samples
  ([Token Weather](https://github.com/anthropics/claude-code-playground/tree/569c5283d9a0a7ee7938df85bb32e4f48cbb8c86/claude-code/mods/token-weather),
  [Blast Radius](https://github.com/anthropics/claude-code-playground/tree/569c5283d9a0a7ee7938df85bb32e4f48cbb8c86/claude-code/mods/blast-radius),
  [Replay Theater](https://github.com/anthropics/claude-code-playground/tree/569c5283d9a0a7ee7938df85bb32e4f48cbb8c86/claude-code/mods/replay-theater));
  for built-in mods, see
  [`mods/diff`](https://github.com/anthropics/claude-code/tree/dd6bee38458cc3e6dc5f2b16eca1f0f364619ad8/mods/diff)
  and
  [`mods/agents-md`](https://github.com/anthropics/claude-code/tree/dd6bee38458cc3e6dc5f2b16eca1f0f364619ad8/mods/agents-md).
- **As of**: 2026-10-17, Claude Code 2.1.302 (playground `569c5283d9a0`, claude-code `dd6bee38458c`)
- **Recheck trigger**: a pinned directory is renamed or removed upstream, or either repository
  changes its license.

Before loading a mod this repository did not write, a sample mod included, run
`claude plugin validate` on its directory and read what its `hooks:` and `calls:` lines let it do.
For mods already installed, `/harness-ops:audit-mod-posture` lists what each one on the machine
hooks and calls, and whether the built-in guard is seated. After installing or updating a mod from the shell while a session is open, follow the reload
step upstream gives for that case.

- **Pointer**: for what a loaded mod can reach, see
  [overview: what a mod can reach](https://code.claude.com/docs/en/plugins/mods/overview#what-a-mod-can-reach);
  for listing hooks and calls before loading, see
  [overview: list what a mod does before you install one](https://code.claude.com/docs/en/plugins/mods/overview#list-what-a-mod-does-before-you-install-one);
  for what each `calls:` entry means, see
  [admin: review what a mod can do](https://code.claude.com/docs/en/plugins/mods/admin#review-what-a-mod-can-do);
  for the reload after a shell-side install or update, see
  [overview: install or update a mod](https://code.claude.com/docs/en/plugins/mods/overview#install-or-update-a-mod).
- **As of**: 2026-10-25, Claude Code 2.1.310
- **Recheck trigger**: a linked section moves, or `/harness-ops:audit-mod-posture` stops reading
  the `hooks:` and `calls:` lines.

## Mod, settings hook, or skill

Apply ADR 0052's rule for choosing a mod, which starts from upstream's comparison table.

- **Pointer**: see
  [overview: compare mods, settings hooks, skills, and MCP servers](https://code.claude.com/docs/en/plugins/mods/overview#compare-mods-settings-hooks-skills-and-mcp-servers).
- **As of**: 2026-10-03, Claude Code 2.1.288
- **Recheck trigger**: the comparison table changes a "Pick it when" cell.

## Where a mod runs and how it is switched off

State in the plugin's README which session types it was tested in. A plugin with `PreToolUse`
settings hooks says in its README that a mod can keep them from running and can approve a call they
blocked. Setting `CLAUDE_CODE_PLUGIN_DIRS` in `~/.claude/settings.json` to load a mod in the Desktop
app is a user-scope change and needs the user's approval.

- **Pointer**: for session types, see
  [overview: where mods run](https://code.claude.com/docs/en/plugins/mods/overview#where-mods-run);
  for switches and the minimum version, see
  [overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off);
  for settings hooks in the chain, see
  [events: where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)
  and
  [events: approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked);
  for `CLAUDE_CODE_PLUGIN_DIRS`, see
  [reference: settings and environment variables](https://code.claude.com/docs/en/plugins/mods/reference#settings-and-environment-variables).
- **As of**: 2026-10-03, Claude Code 2.1.288. `--bg` sessions and the Desktop app were not probed.
- **Recheck trigger**: the where-mods-run table changes a row, the minimum version changes, or the
  settings-hooks section changes where plugin `PreToolUse` hooks run.

The switches that stop installed mods differ from those that stop built-in mods. When a mod passes
`claude plugin test` and does nothing on a machine with managed settings or a Team or Enterprise
login, check the organization's mod policy and the built-in guard's messages before debugging the
mod.

- **Pointer**: for built-in mods and how each is switched off, see
  [overview: mods built into Claude Code](https://code.claude.com/docs/en/plugins/mods/overview#mods-built-into-claude-code);
  for the policy `claude plugin test` does not report, see
  [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load)
  and
  [admin: allow only your organization's mods](https://code.claude.com/docs/en/plugins/mods/admin#allow-only-your-organization%E2%80%99s-mods);
  for the guard's messages, see
  [troubleshoot: messages from the built-in guard](https://code.claude.com/docs/en/plugins/mods/troubleshoot#messages-from-the-built-in-guard).
- **As of**: 2026-10-25, Claude Code 2.1.310
- **Recheck trigger**: a linked section moves, or `claude plugin test` starts reporting the
  organization's mod policy.

## Packaging in this repository

- Lay out the plugin as the reference page's files table says. Commit the root `tsconfig.json`
  Claude Code writes; never commit `.claude-plugin/types/`.
- Declare Claude Code 2.1.287 as the floor in the plugin's README with the version tested against.
- `scripts/validate-plugins.sh` runs `claude plugin validate --json` on every plugin, then
  `scripts/test-plugin-mods.sh`, which runs `claude plugin test` on every plugin whose `hooks.json`
  names `modules`. CI runs it with the CLI pinned in `package.json`; a local run on the current
  release catches a release newer than the pin.

- **Pointer**: for the files, see
  [reference: files](https://code.claude.com/docs/en/plugins/mods/reference#files); for names
  `validate` refuses and the tested-version note, see
  [create: share your mod](https://code.claude.com/docs/en/plugins/mods/create#share-your-mod).
- **As of**: 2026-10-03, Claude Code 2.1.288
- **Recheck trigger**: the files table changes a row, or `validate` accepts or rejects a different
  name shape.

## Before relying on `$.process` or `session.start`

A mod that starts programs or restores state at session start reads these two upstream statements
first: `$.process` is declared CLI only, and `session.start` does not fire again after `/clear`,
`/resume` or `/branch`.

- **Pointer**: for `$.process`, see the doc comment on `process` in
  [`mods/types/claude-code.d.ts`](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts)
  (the build's own `.claude-plugin/types/claude-code/index.d.ts` carries the same comment); for
  `session.start`, see
  [reference: session](https://code.claude.com/docs/en/plugins/mods/reference#session) and
  [interface: load a saved value again after `/clear`](https://code.claude.com/docs/en/plugins/mods/interface#load-a-saved-value-again-after-clear).
- **As of**: 2026-10-03, Claude Code 2.1.288 (the public types file's first line names 2.1.277)
- **Recheck trigger**: a pin bump whose types change the `process` doc comment, or the Session table
  changes its `session.start` row.

## The `tool.call` context rule

A `tool.call` hook that adds context appends to what `next` returned:
`context: [...(result.context ?? []), line]`. Returning `context: [line]` makes the engine skip that
hook's answer whenever a mod below it attached a line, so the line is lost. The types state only
that `context` is kept whole from `next`; neither the types nor the docs state the consequence, that
the engine skips the hook's answer and logs `hook failed closed`. The evidence for it is
[E9](../../upstream/claude-code-mods/experiments.md#e9-two-mods-adding-toolcall-context-2026-10-03).

- **Pointer**: for "Kept whole from `next`", see the doc comment on the `tool.call` result's
  `context` in
  [`mods/types/claude-code.d.ts`](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts).
- **As of**: 2026-10-03, Claude Code 2.1.288 (the public types file's first line names 2.1.277)
- **Recheck trigger**: re-run E9 on a pin bump whose types change that comment, or when a docs page
  states the consequence.

## When a mod does nothing or misbehaves

Look up a log, toast or refusal line by its text on the troubleshoot page, whose headings are those
texts. A mod writes its own diagnostics to the debug log, not the transcript. A mod that registers
an agent does so from its `session.start` hook. Work a mod starts on its own after the user stops a
turn follows the API's interrupt rules. A load problem that is not specific to mods goes to the
plugin troubleshooting page.

- **Pointer**: for the debug log, see
  [troubleshoot: read the debug log](https://code.claude.com/docs/en/plugins/mods/troubleshoot#read-the-debug-log)
  and, for writing to it,
  [api: show something without starting a turn](https://code.claude.com/docs/en/plugins/mods/api#show-something-without-starting-a-turn);
  for agent registration, see
  [troubleshoot: `$.agent.register refused`](https://code.claude.com/docs/en/plugins/mods/troubleshoot#$-agent-register-refused-the-hooks-module-that-made-the-call-is-no-longer-loaded);
  for work after an interrupt, see
  [api: calls and background work after the user interrupts a turn](https://code.claude.com/docs/en/plugins/mods/api#calls-and-background-work-after-the-user-interrupts-a-turn)
  and
  [troubleshoot: a toast appears after a turn is stopped](https://code.claude.com/docs/en/plugins/mods/troubleshoot#a-toast-appears-after-a-turn-is-stopped);
  for the line a failing hook leaves, see
  [events: handle a hook that fails](https://code.claude.com/docs/en/plugins/mods/events#handle-a-hook-that-fails);
  for plugin load problems, see
  [troubleshoot plugins](https://code.claude.com/docs/en/plugins/troubleshooting).
- **As of**: 2026-10-25, Claude Code 2.1.310
- **Recheck trigger**: a linked section moves, or the troubleshoot page stops titling its sections
  with the line texts.
