# Mod authoring: writing a hooks module in a marketplace plugin

Owner doc for **how a plugin in this marketplace ships a mod**: a hooks module of function hooks
that Claude Code calls in its own process. Anthropic owns the mods API and ships the authoring
guide inside Claude Code; this doc covers only what that guide cannot know about this repository.

## Scope

A mod in this repository follows the five scope rules in
[ADR 0046](../../adr/0046-adopt-claude-code-mods-within-five-scope-rules.md#scope-rules). This doc
does not restate them; read them before writing a mod, and re-read them before changing one. The
first mod is the `usage-band` pilot in
[#5777](https://github.com/melodic-software/claude-code-plugins/issues/5777).

## Boundary

- **The API itself**: events, `$` methods, render sites, limits. The built-in `plugin-authoring`
  skill and the upstream pages below own it. This doc restates none of it.
- **What a mod may do here**: ADR 0046 owns the scope rules.
- **Settings hooks** (`hooks` in `hooks.json`, shell or HTTP): the `hook-*` conventions own their
  cost, precision, input rewriting, observability and telemetry, starting with
  [hook-budget](../hook-budget/README.md).
- **Records of upstream facts**: [upstream-drift](../upstream-drift/README.md) owns the record
  shape each pointer below carries.

## Before writing or changing a mod

1. **Load the built-in `plugin-authoring` skill** (`/plugin-authoring`, or the Skill tool). Claude
   Code regenerates it for each build with that build's type declarations, so it is the authority
   for what the running version supports. A copy of the API in this repository would drift every
   release.
2. **Read the upstream pages** for the parts you touch, as raw markdown:
   [overview](https://code.claude.com/docs/en/plugins/mods/overview.md),
   [create](https://code.claude.com/docs/en/plugins/mods/create.md),
   [events](https://code.claude.com/docs/en/plugins/mods/events.md),
   [interface](https://code.claude.com/docs/en/plugins/mods/interface.md),
   [api](https://code.claude.com/docs/en/plugins/mods/api.md),
   [reference](https://code.claude.com/docs/en/plugins/mods/reference.md),
   [test](https://code.claude.com/docs/en/plugins/mods/test.md),
   [admin](https://code.claude.com/docs/en/plugins/mods/admin.md),
   [troubleshoot](https://code.claude.com/docs/en/plugins/mods/troubleshoot.md). When a page and
   the skill's declaration files disagree, the declaration files win.
3. **Check the mod against the scope rules** with `claude plugin validate`: its `hooks:` line shows
   every `tool.call` filter, and its `calls:` line shows every `$` method the module calls.

- **Pointer**: for which source wins when a page and the declarations disagree, see
  [create: get type definitions for your version](https://code.claude.com/docs/en/plugins/mods/create#get-the-types-for-your-build);
  for the `hooks:` and `calls:` lines, see
  [create: check what Claude Code reads from your mod](https://code.claude.com/docs/en/plugins/mods/create#check-what-claude-code-reads-from-your-mod).
- **As of**: 2026-10-02, Claude Code 2.1.288
- **Recheck trigger**: either section moves, or `claude plugin validate` stops listing hooks and
  calls.

## Settings hook or mod

Use a **settings hook** when a script can block, allow, rewrite or log an event: guards,
formatters, loggers. A guard is always a settings hook (ADR 0046 rule 4). A settings hook also runs
where an organization stops user-installed mods, and the repo's shell test and budget tooling
covers it.

Use a **mod** only for what a settings hook cannot do: draw a pane, band, status entry or toast;
register a command or a tool; rewrite a prompt section, turn or model request; or read in-process
state such as `$.session.usage()`. A mod that replaces an existing hook keeps the hook as the
fallback, in the hook's own plugin, until the mod's behavior is verified in every session type the
plugin serves.

- **Pointer**: for when to pick each, see
  [overview: compare mods, settings hooks, skills, and MCP servers](https://code.claude.com/docs/en/plugins/mods/overview#compare-mods-settings-hooks-skills-and-mcp-servers);
  for the status entry and the toast, see
  [api: show something without starting a turn](https://code.claude.com/docs/en/plugins/mods/api#show-something-without-starting-a-turn);
  for what an organization's mod block leaves running, see
  [admin: stop user-installed mods from loading](https://code.claude.com/docs/en/plugins/mods/admin#stop-user-installed-mods-from-loading).
- **As of**: 2026-10-02, Claude Code 2.1.288
- **Recheck trigger**: the comparison table changes either "Pick it when" cell, a release lets a
  settings hook draw in the interface, or the admin section starts stopping settings hooks.

## Where a mod runs

Before relying on what a mod draws, read which session types run its hooks and which show its
drawing, Desktop sessions in WSL included, and state in the plugin's README where it was tested. To
load a mod directory in the Desktop app without installing it, read the `CLAUDE_CODE_PLUGIN_DIRS`
row. Setting that variable in `~/.claude/settings.json` is a user-scope change, so it needs the
user's approval.

- **Pointer**: for the session types, see
  [overview: where mods run](https://code.claude.com/docs/en/plugins/mods/overview#where-mods-run);
  for `CLAUDE_CODE_PLUGIN_DIRS`, see
  [reference: settings and environment variables](https://code.claude.com/docs/en/plugins/mods/reference#settings-and-environment-variables);
  for the Desktop app as an app that takes no `--plugin-dir`, see the 2.1.288 `plugin-authoring`
  skill's `reference.md` (line 68).
- **As of**: 2026-10-02, Claude Code 2.1.288. `--bg` sessions and Desktop were not probed.
- **Recheck trigger**: the where-mods-run table adds, drops or changes a row, the
  `CLAUDE_CODE_PLUGIN_DIRS` row changes, or `reference.md` stops naming the Desktop app.

## Packaging

- A mod is its own plugin (ADR 0046 rule 1). Lay out its manifest, `hooks/hooks.json`, hooks
  module, optional types contract and tests as the reference page's files table says, and give the
  plugin a name `claude plugin validate` accepts.
- `scripts/validate-plugins.sh` runs `claude plugin validate --json` on every plugin, then
  `scripts/test-plugin-mods.sh`, which runs `claude plugin test` on every plugin whose `hooks.json`
  names `modules`. No plugin ships one yet, so the test step skips; it also skips when the CLI on
  `PATH` is older than 2.1.287.

- **Pointer**: for the file layout, see
  [reference: files](https://code.claude.com/docs/en/plugins/mods/reference#files); for the names
  `validate` refuses, see [create: share your mod](https://code.claude.com/docs/en/plugins/mods/create#share-your-mod).
- **As of**: 2026-10-02, Claude Code 2.1.288
- **Recheck trigger**: the files table changes a row, or `claude plugin validate` accepts or
  rejects a different name shape.

## Version floor and stability

- Mods need Claude Code **2.1.287** or later. State the minimum in the plugin's README with the
  version you tested against.
- ADR 0046 judges stability on the docs pages and the per-build types header, not on the upstream
  `mods/README.md`. The 2.1.288 types header still carries an early-access line, which ADR 0046
  accepted at adoption; read the create page's stability statement before relying on an event or
  method.
- **Recheck on every Claude Code release** that touches mods: reload `plugin-authoring`, run
  `claude plugin validate` and `claude plugin test` on each mod, and re-stamp this doc. CI runs
  `claude plugin test` with the CLI pinned in `package.json`, so a local run on the current
  release is what catches a release newer than the pin.

- **Pointer**: for the minimum version, see
  [overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off)
  and [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load);
  for the stability statement, see
  [create: share your mod](https://code.claude.com/docs/en/plugins/mods/create#share-your-mod)
  and line 4 of the `plugin-authoring` skill's `types/claude-code.d.ts`.
- **As of**: 2026-10-02, Claude Code 2.1.288
- **Recheck trigger**: the overview changes its minimum version, the types header drops or changes
  its early-access line, or a docs page adds an early-access warning.
