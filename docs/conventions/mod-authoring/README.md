# Mod authoring: writing a hooks module in a marketplace plugin

Owner doc for **how a plugin in this marketplace would ship a mod**: a hooks module of function
hooks that Claude Code calls in its own process. Anthropic owns the mods API and ships the
authoring guide inside Claude Code; this doc covers only what that guide cannot know about this
repository.

## Mods are deferred

This doc does not authorize a mod. [ADR 0035](../../adr/0035-defer-claude-code-mods-with-five-go-criteria.md)
still defers mods: no plugin under `plugins/` gains a `modules` key until all five go criteria in
the [Mods row of the Native-first table](../../plugin-philosophy.md) hold, checked with
[go-no-go.md](../../upstream/claude-code-mods/go-no-go.md). The pilot in
[#5777](https://github.com/melodic-software/claude-code-plugins/issues/5777) is how those criteria
get evaluated, and it stays under `.work/` until they pass. The rest of this doc is the how-to for
when they do, and for that pilot.

## Boundary

- **The API itself**: events, `$` methods, render sites, limits. The built-in `plugin-authoring`
  skill and the upstream pages below own it. This doc restates none of it.
- **Settings hooks** (`hooks` in `hooks.json`, shell or HTTP): the `hook-*` conventions own their
  cost, precision, input rewriting, observability and telemetry, starting with
  [hook-budget](../hook-budget/README.md).
- **Stamps on upstream facts**: [upstream-drift](../upstream-drift/README.md) owns the four-part
  record each claim below carries.

## Before writing or changing a mod

1. **Load the built-in `plugin-authoring` skill** (`/plugin-authoring`, or the Skill tool). Claude
   Code regenerates it for each build with that build's type declarations, so it is the authority
   for what the running version supports. A copy of the API in this repository would drift every
   release.
2. **Read the upstream pages** for the parts you touch, as raw markdown:
   [overview](https://code.claude.com/docs/en/plugins/mods/overview.md),
   [create](https://code.claude.com/docs/en/plugins/mods/create.md),
   [reference](https://code.claude.com/docs/en/plugins/mods/reference.md),
   [test](https://code.claude.com/docs/en/plugins/mods/test.md),
   [admin](https://code.claude.com/docs/en/plugins/mods/admin.md),
   [troubleshoot](https://code.claude.com/docs/en/plugins/mods/troubleshoot.md). When a page and the skill's
   declaration files disagree, the declaration files win.

## Settings hook or mod

Use a **settings hook** when a script can block, allow, rewrite or log an event: guards,
formatters, loggers. It runs where mods do not load (under an organization's
`allowManagedModsOnly`, or on a Claude Code older than the minimum below), and the repo's shell
test and budget tooling covers it.

Use a **mod** only for what a settings hook cannot do: draw a pane, band, status entry or toast;
register a command or tool; rewrite a prompt section, turn or model request; or read in-process
state such as `$.session.usage()`. A mod that replaces an existing hook keeps
the hook as the fallback until the mod's behavior is verified in every session type the plugin
serves.

Basis: the overview's "Compare mods, settings hooks, skills, and MCP servers" table ("Pick it
when ... You want a pane, a band above the prompt, a custom command, or to rewrite an event" for a
mod; "You want to block, allow, or log an event with a script you already have" for a settings
hook); the admin page's `allowManagedModsOnly` row ("No installed mods, with hooks untouched").
Verified 2026-10-01 against Claude Code 2.1.287. Recheck trigger: that table changes either
"Pick it when" cell, a release lets a settings hook draw in the interface, or
`allowManagedModsOnly` starts stopping settings hooks.

## Packaging

- The module lives in the plugin's `hooks/` directory and is named by `hooks/hooks.json`:
  `"modules": ["./register.ts"]`, one path relative to `hooks.json`. The same file can keep
  settings hooks under `hooks`.
- `types/index.d.ts`, named by `types` in `plugin.json`, when the mod uses `$.state` or adds a
  namespace. Tests are `*.test.ts` or `*.test.tsx` beside the module.
- The plugin name must not start with `claude-`; `claude plugin validate` rejects it.
- `scripts/validate-plugins.sh` runs `claude plugin validate --json` on every plugin and
  `claude plugin test` on every plugin whose `hooks.json` names `modules`. Under ADR 0035 none
  does, so the test step skips; it exists so the first mod that clears the go criteria is tested.

Basis: the reference page's "Files" table ("`modules`: an array with one path, relative to this
file, to the hooks module") and the create page ("`claude plugin validate` fails a name that looks
like one of Anthropic's own, such as one that starts with `claude-`"). Verified 2026-10-01 against
Claude Code 2.1.287. Recheck trigger: the "Files" table changes a row, or `claude plugin validate`
accepts or rejects a different name shape.

## Version floor and stability

- Mods need Claude Code **2.1.287** or later; older versions predate mods being on by default.
  State the minimum in the plugin's README with the version you tested against.
- The API is early access. The types header reads "EARLY ACCESS: this surface may change between
  releases without notice", and the create page says "The events and methods can change between
  releases".
- **Recheck on every Claude Code release** that touches mods: reload `plugin-authoring`, run
  `claude plugin validate` and `claude plugin test` on each mod, and re-stamp this doc. CI runs
  `claude plugin test` only when its pinned CLI is at least 2.1.287 and skips with a notice
  otherwise, so a local run on the current release is the check that counts.

Basis: the overview ("Mods require Claude Code v2.1.287 or later, and they're on by default"), the
troubleshoot page ("Your version predates mods being on by default"), and the
`plugin-authoring` skill's `types/claude-code.d.ts` line 4 in 2.1.287. Verified 2026-10-01. Recheck
trigger: the overview changes its minimum version, or the types header drops "EARLY ACCESS".
