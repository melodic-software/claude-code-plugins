# The built-in `/context` command: verification record

Detail behind the `/context` `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a
four-part record: the claim, the basis it rests on, the date it was checked, and the event that
makes it worth checking again. Nothing here asserts the command is present in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `/context` is a built-in command: "Visualize current context usage as a colored grid", argument hint `[all]`, gated | The `/harness-ops:inventory` extraction of the installed 2.1.285 binary, 2026-09-29 (`builtin_commands` lane) | 2026-09-29 | A release renames or removes the command, or changes its description or gate |
| It is user-invocable only; model invocation is disabled (command type `local-jsx`) | The same extraction (`user_invocable` true, `model_invocable` false) | 2026-09-29 | A release makes it model-invocable |
| It shows optimization suggestions for context-heavy tools, memory bloat, and capacity warnings, and `all` expands the per-item breakdown | The `/context [all]` row on <https://code.claude.com/docs/en/commands> | 2026-09-30 | The row changes its description or arguments |
| It shows the current session only; nothing in its description measures a fresh session's startup payload or compares two configurations | The description and docs row above | 2026-09-30 | A release widens it to startup cost or a before/after comparison |

## Why the verdict is complementary

Both show what fills a context window. `/context` shows the current session, live, as a grid the
person reads. This skill measures the fixed payload every session starts with, per item, by A/B
differencing headless sessions, splits the tool pools `/context` reports as lump sums, and ledgers
the measured delta of each lever. The model cannot run `/context`, so this skill offers it to the
person instead of routing to it.
