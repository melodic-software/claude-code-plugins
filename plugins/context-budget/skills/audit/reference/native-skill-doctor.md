# The built-in `/skill-doctor` command: verification record

Detail behind the `skill-doctor` `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a
four-part record: our decision or our probe's observation, the pointer or probe it rests on, the
date it was derived, and the event that makes it worth deriving again. No row restates an upstream
page; read the specific live at the pointer. Nothing here asserts the command is present in any
session.

| Decision or observation | Pointer or probe | As of | Recheck when |
|---|---|---|---|
| Our probe found `/skill-doctor` as a built-in command, user-invocable, with model invocation disabled (command type `local-jsx`); the probe set no `gated` flag for it | Probe: the `/harness-ops:inventory --binary-only` extraction of the installed 2.1.285 binary, `builtin_commands` lane | 2026-10-02 | A release renames or removes the command, or makes it model-invocable |
| We send the choice of which skills to turn off to `/skill-doctor`, and never make that choice here | For skill pruning, see <https://code.claude.com/docs/en/skills#find-unused-skills> | 2026-10-02 | That section sends the question to another command, or the command's job there changes |
| We treat it as gated and never assert it present; the gate is read live, not copied here | For its gate, see the `/skill-doctor` row on <https://code.claude.com/docs/en/commands> and <https://code.claude.com/docs/en/skills#find-unused-skills> | 2026-10-02 | Either page changes the command's version floor or flag requirement |
| We keep unused MCP servers and plugins routed to the bundled `/doctor` | For `/doctor`, see its row on <https://code.claude.com/docs/en/commands> | 2026-10-02 | That row drops its unused-component check, or a release note names `/doctor` |

## Why the verdict is complementary

The two meet only on skills. We assign the pruning choice to the native command and keep, here,
the measurement of a fresh session's startup payload, the split of the built-in tool pools, and the
ledger of what a toggle measurably saved. The model cannot run `/skill-doctor`, so this skill
offers it to the person instead of routing to it. Recheck when the pointer section above starts
covering startup measurement or a before/after comparison.
