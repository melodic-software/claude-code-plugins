# The bundled `debug` skill: verification record

Detail behind the `## Boundary, the bundled \`debug\` skill` section in [SKILL.md](../SKILL.md).
Each row is a four-part record: the claim, the basis it rests on, the date it was checked, and the
event that makes it worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `debug` is a bundled skill that diagnoses Claude Code's own runtime from its session debug log, an object this skill never debugs; what it enables, when logging starts, and its arguments are read from its row | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary (2026-09-29: description "Enable debug logging for this session and help diagnose issues", argument hint `[issue description]`). Pointer: the `/debug` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | The commands page row changes, or a release renames or removes the skill |
| It is reserved for the person to run: its registration disables model invocation | The same extraction (`model_invocable: false`, `disable_model_invocation: true`, `user_invocable: true`) | 2026-09-29 | A release makes it model-invocable |
| It is not gated in the extraction, but a consumer's settings can remove or hide it, so the Boundary section never assumes it resolves | The same extraction (`gated: false`, 2026-09-29). Pointer: the settings are read at [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) and [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings) | 2026-10-11 | Either section changes the bundled-skill switches, or a release gates the skill |

## Why the verdict is complementary

Both answer "why is this broken", on different objects. The bundled skill diagnoses Claude Code's
own runtime from its debug log. This skill diagnoses the user's application through a
reproduction loop. Neither replaces the other; the routing question is which system misbehaves.
