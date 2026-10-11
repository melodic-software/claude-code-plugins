# The built-in `/bug` command: verification record

Detail behind the `/bug` Boundary section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. "The extraction" below is the `/harness-ops:inventory` extraction of the
installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `bug` is a built-in command of type `local-jsx`, alias `share`, argument hint `[report]`, described as "Report a bug or share your conversation". User-invocable only (not model-invocable), not hidden, not gated | The extraction | 2026-09-29 | A release renames it, changes its alias, or changes its invocability |
| We route defects in Claude Code itself to `/bug` and never describe its destination or contents ourselves; both are read from its row | Pointer: the `/bug` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | That row changes or is removed |

## Why the verdict is complementary

`/bug` reports on Claude Code itself. This skill reports on the person's own
code, for the person or their tracker. The words overlap and the jobs do not, so the model offers
`/bug` only when the defect is in Claude Code itself.
