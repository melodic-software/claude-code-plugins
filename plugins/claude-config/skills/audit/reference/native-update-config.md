# The bundled `update-config` skill, as this skill relates to it

Four-part records behind the `update-config` Boundary section in `SKILL.md`. The section carries
the conclusion; this file carries what it rests on. Nothing here asserts that the surface is present
in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `update-config` is a bundled skill, invocable by the model and the person, not gated | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: true`, `user_invocable: true`, `gated: false`) | 2026-09-29, Claude Code 2.1.284 | A release renames or removes the skill, or changes its invocability |
| It configures the harness through `settings.json`: hooks for automated behaviors, permissions, environment variables, hook troubleshooting, and any change to `settings.json` or `settings.local.json`; for theme and model it points to `/config` | The same binary extraction's description | 2026-09-29, Claude Code 2.1.284 | A release changes the skill's description |
| Given a described settings change, Claude edits the matching `settings.json` file | Its commands reference row, <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes |
| It writes `Edit(path)` permission rules, not `Write(path)` rules, for file permissions | Claude Code changelog 2.1.275 | 2026-09-29 | A release note changes the rule shape it writes |

## Why the verdict is complementary

`update-config` makes a change the person asks for. This skill checks what is already configured
against current docs and the project's conventions and reports findings; its `--fix` phase applies
only findings it produced, each behind a confirmation. One writes on request, the other judges the
result, so an audit finding the person wants fixed in a way `--fix` does not cover is a natural
request to hand to `update-config`, which the person or the model makes as a new request, not a
chain from this skill.

## Presence

Bundled skills can be removed by `disableBundledSkills` or hidden by `skillOverrides`, and vary by
version and host, so the routing reads "when the surface resolves in this session" and never that
it is present. Recheck when a release or docs change adds, removes, or renames a gating axis.
