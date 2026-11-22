# Mod posture checklist

Criteria M1-M8 for `/harness-ops:audit-mod-posture`, judged from the inventory TSV. Each names
the column it reads and its severity rule. Why a hook, call or guard state matters is upstream's to
say: each criterion's Details cell links its source record below instead of restating it.

## Severity

- **WARN**. Read it first.
- **info**. Worth knowing; no change expected.
- **PASS**. Criterion met.
- **n/a**. The row has nothing to judge (for example M2 on a mod with no hooks).

Rows with `enabled = off` get no M2 to M4, M7 or M8 findings. Built-in rows are scored at most
info; the action for one is turning it off where `can_disable` is `yes`.

## M1 Guard not seated

Reads the `# guard:` footer, once per run.

| Footer | Result |
|---|---|
| `seated (...)` | PASS |
| `seated (...; mods can override deny rules: ...)` | WARN: the guard's `allowModsToOverrideDenyRules` option is on; link the guard-options record |
| `not-seated (managed prependPlugins omits the guard)` | WARN: managed `prependPlugins` does not name the guard; link the guard-options record |
| `not-seated (...)` | WARN; link the defaults record |
| `unknown (...)` | WARN, labeled unverified; name the unread source from the basis |

## M2 Hooks tool.check or tool.call

Reads `hooks`. A row listing `tool.check` or `tool.call`, with or without a `{...}` filter: WARN
for an installed mod, info for a built-in; link the review record. PASS otherwise; `unknown` hooks,
or a `redacted` entry, read WARN, labeled unverified.

## M3 Hooks prompt.submit or session.append

Reads `hooks`. A row listing `prompt.submit` or `session.append`: same severities and link as
M2.

## M4 Calls $.fs or $.process

Reads `calls`. A row listing any `$.fs.` or `$.process.` method: info, whatever the `# guard:`
footer says, naming the methods and linking the defaults record for what deny rules and managed
hooks cover. `unknown` (every built-in row) or a `redacted` entry reads info, "calls not read".

## M5 Inventory

The table itself. Not scored.

## M6 Claude-written mods load unasked

Reads the `# claude-written mods:` footer, once per run. The script derives it from
`permissions.defaultMode` (managed settings, else user settings, unless project or local settings
set a mode other than `auto` or `bypassPermissions`, which then wins) and managed
`disableSideloadFlags`.

| Footer | Result |
|---|---|
| `not-unasked (...)` | PASS |
| `load-unasked (...)` | WARN: a mod Claude writes in a session loads without asking; name the mode and link the create record and the sideload record |
| `unknown (...)` | WARN, labeled unverified; name the unread source from the basis |

## M7 Calls $.tool.call or $.mcp.call

Reads `calls`. A row listing `$.tool.call` or `$.mcp.call`: info, whatever the `# guard:` footer
says, naming the methods and linking the defaults record for which checks those calls skip.
`unknown` or a `redacted` entry reads info, "calls not read".

## M8 Noun overrides

Reads `nouns`: each entry is `add:`, `withhold:` or `replace:` and a `$` namespace the mod's
`engine.create` hook changes. `add:` entries: info, naming the namespaces. Any `withhold:` or
`replace:` entry: WARN, naming each namespace; link the engine record. `-` is n/a. `unknown` (every
built-in row) or a `redacted` entry reads info, "nouns not read".

## Source records

- **Pointer** (the review record): for what each hook and call means, fetch
  [Manage mods for your organization: Review what a mod can do](https://code.claude.com/docs/en/plugins/mods/admin#review-what-a-mod-can-do)
  live.
- **As of**: 2026-10-17
- **Recheck trigger**: that section adds or drops a hook or call it singles out, or changes what
  `tool.check`, `tool.call`, `prompt.submit` or `session.append` allows.

- **Pointer** (the guard-options record): for the guard's options and how `prependPlugins` must
  name it, fetch
  [Manage mods for your organization: Set options on the built-in guard](https://code.claude.com/docs/en/plugins/mods/admin#set-options-on-the-built-in-guard)
  live.
- **As of**: 2026-10-17
- **Recheck trigger**: that section renames `allowModsToOverrideDenyRules`, moves the options out
  of `pluginConfigs` under `cc-plugin-sec-default@builtin`, or stops requiring `prependPlugins` to
  name the guard.

- **Pointer**: for which built-in mods exist and how each is turned off (the source of
  `can_disable`), fetch
  [Mods overview: Mods built into Claude Code](https://code.claude.com/docs/en/plugins/mods/overview#mods-built-into-claude-code)
  live.
- **As of**: 2026-10-17
- **Recheck trigger**: that table renames or drops its "How to turn it off" column, or stops
  starting a can't-disable entry with "You can't".

- **Pointer** (the defaults record): for when the guard loads and what deny rules and managed hooks
  cover, including a mod's own `$.fs`, `$.process`, `$.tool.call` and `$.mcp.call` calls, fetch
  [Manage mods for your organization: Know what happens by default](https://code.claude.com/docs/en/plugins/mods/admin#know-what-happens-by-default)
  live.

- **Pointer** (the create record): for which permission modes load a mod Claude writes without
  asking and which sessions never load one, fetch
  [Create a mod: Ask Claude for a mod](https://code.claude.com/docs/en/plugins/mods/create#ask-claude-for-a-mod)
  live.
- **As of**: 2026-11-22
- **Recheck trigger**: that section changes which modes skip the hot reloading question, or where
  Claude writes the mods.

- **Pointer** (the sideload record): for what `disableSideloadFlags` rejects, and that only managed
  settings set it, fetch
  [Settings reference: disableSideloadFlags](https://code.claude.com/docs/en/settings-reference#disablesideloadflags)
  live. For why the script takes `auto` and `bypassPermissions` from managed and user settings
  only, while a lower mode in project or local settings still wins, see
  [the same page's `permissions.defaultMode` entry](https://code.claude.com/docs/en/settings-reference#permissions-defaultmode).
- **As of**: 2026-11-22
- **Recheck trigger**: `disableSideloadFlags` stops keeping Claude-written mods from loading or
  takes a scope other than Managed, or `auto` and `bypassPermissions` start taking effect from
  project or local settings.

- **Pointer** (the engine record): for what an `engine.create` hook may change on `$` and which tiers
  may withhold a namespace, fetch
  [Mods reference: Other mods](https://code.claude.com/docs/en/plugins/mods/reference#other-mods)
  live.
- **As of**: 2026-11-22
- **Recheck trigger**: that row lets the `user` tier withhold a namespace, or `claude plugin validate`
  renames its `adds to $:`, `withholds from $:` or `replaces on $:` lines.
