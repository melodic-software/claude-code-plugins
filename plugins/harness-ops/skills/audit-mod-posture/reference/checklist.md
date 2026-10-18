# Mod posture checklist

Criteria M1-M5 for `/harness-ops:audit-mod-posture`, judged from the inventory TSV. Each names
its severity rule and the column it reads.

## Severity

- **WARN**. A mod or a missing guard can decide or rewrite what Claude does. Read it first.
- **info**. Worth knowing; no change expected.
- **PASS**. Criterion met.
- **n/a**. The row has nothing to judge (for example M2 on a mod with no hooks).

Rows with `enabled = off` get no M2 to M4 findings. Built-in rows are scored at most info: they
ship with Claude Code and the operator's lever is turning them off where `can_disable` is `yes`.

## M1 Guard not seated

Reads the `# guard:` footer, once per run.

| Footer | Result |
|---|---|
| `seated (...)` | PASS |
| `not-seated (...)` | WARN: a user's mod can approve a tool call that a deny rule refuses |
| `unknown (...)` | WARN, labeled unverified; name the unread source from the basis |

## M2 Hooks tool.check or tool.call

Reads `hooks`. A row listing `tool.check` or `tool.call` (with or without a `{...}` filter) can
approve, deny or rewrite Claude's tool calls. WARN for an installed mod, info for a built-in,
PASS otherwise; `unknown` hooks read WARN, labeled unverified.

## M3 Hooks prompt.submit or session.append

Reads `hooks`. A row listing `prompt.submit` or `session.append` sees and can rewrite prompts or
stored conversation rows. Same severities as M2.

## M4 Calls $.fs or $.process

Reads `calls`. A row listing any `$.fs.` or `$.process.` method reaches files and processes as the
user, outside every deny rule and managed hook, whether or not the guard is seated. info, always
stated with that sentence; `unknown` (every built-in row) reads info, "calls not read".

## M5 Inventory

The table itself. Not scored.

## Source records

- **Pointer**: for what each hook and call means, fetch
  [Manage mods for your organization: Review what a mod can do](https://code.claude.com/docs/en/plugins/mods/admin#review-what-a-mod-can-do)
  live.
- **As of**: 2026-10-17
- **Recheck trigger**: that section adds or drops a hook or call it singles out, or changes what
  `tool.check`, `tool.call`, `prompt.submit` or `session.append` allows.

- **Pointer**: for which built-in mods exist and how each is turned off (the source of
  `can_disable`), fetch
  [Mods overview: Mods built into Claude Code](https://code.claude.com/docs/en/plugins/mods/overview#mods-built-into-claude-code)
  live.
- **As of**: 2026-10-17
- **Recheck trigger**: that table renames or drops its "How to turn it off" column, or stops
  starting a can't-disable entry with "You can't".
