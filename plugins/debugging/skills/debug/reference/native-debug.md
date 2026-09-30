# The bundled `debug` skill: verification record

Detail behind the `## Boundary, the bundled \`debug\` skill` section in [SKILL.md](../SKILL.md).
Each row is a four-part record: the claim, the basis it rests on, the date it was checked, and the
event that makes it worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `debug` is a bundled skill that enables debug logging for the current session and troubleshoots issues by reading the session debug log; logging starts from the moment it runs unless the session began with `claude --debug`; an optional description focuses the analysis | The `/debug` row on <https://code.claude.com/docs/en/commands>; the `/claude-ops:inventory` extraction of the installed 2.1.284 binary (description "Enable debug logging for this session and help diagnose issues", argument hint `[issue description]`) | 2026-09-29 | The commands page row changes, or a release renames or removes the skill |
| It is reserved for the person to run: its registration disables model invocation | The same extraction (`model_invocable: false`, `disable_model_invocation: true`, `user_invocable: true`) | 2026-09-29 | A release makes it model-invocable |
| It is not gated in the extraction; `disableBundledSkills` or a `skillOverrides` entry removes or hides it | The same extraction (`gated: false`); the bundled skills section of <https://code.claude.com/docs/en/skills> | 2026-09-29 | Either page changes the bundled-skill switches, or a release gates the skill |

## Why the verdict is complementary

Both answer "why is this broken", on different objects. The bundled skill diagnoses Claude Code's
own runtime from its debug log. This skill diagnoses the user's application through a
reproduction loop. Neither replaces the other; the routing question is which system misbehaves.
