# Mod posture checklist

Criteria M1-M5 for `/harness-ops:audit-mod-posture`, judged from the inventory TSV. Each names
the column it reads and its severity rule. Why a hook, call or guard state matters is upstream's to
say: each criterion's Details cell links its source record below instead of restating it.

## Severity

- **WARN**. Read it first.
- **info**. Worth knowing; no change expected.
- **PASS**. Criterion met.
- **n/a**. The row has nothing to judge (for example M2 on a mod with no hooks).

Rows with `enabled = off` get no M2 to M4 findings. Built-in rows are scored at most info; the
action for one is turning it off where `can_disable` is `yes`.

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
  cover, including a mod's own `$.fs` and `$.process` calls, fetch
  [Manage mods for your organization: Know what happens by default](https://code.claude.com/docs/en/plugins/mods/admin#know-what-happens-by-default)
  live.
- **As of**: 2026-10-17
- **Recheck trigger**: that section changes when the guard loads, or changes what it says deny
  rules or managed hooks cover.
