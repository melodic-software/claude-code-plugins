# The built-in `/plan` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `plan` is a built-in command described as "Enable plan mode or view the current session plan", argument `[open\|<description>]`, no alias | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.plan`) | 2026-09-29 | A release renames or removes `plan`, or changes its description or argument |
| It is user-invocable and not model-invocable, and it is not gated behind a setting | Same extraction: `user_invocable: true`, `model_invocable: false`, `gated: false` | 2026-09-29 | A release changes its invocability or adds a gate |
| `/plan [description]` enters plan mode directly from the prompt; a description starts plan mode on that task | The `/plan [description]` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes, including documenting the `open` argument the binary declares |

## Why the verdict is complementary

`/plan` switches the session into plan mode, a read-only permission mode, or shows the session
plan. It runs no stress-test, assesses no blast radius, and persists no PLAN.md for a cleared
session. This skill is the planning discipline and works inside or outside plan mode, so the skill
offers `/plan` for safe exploration while it plans rather than replacing it.
