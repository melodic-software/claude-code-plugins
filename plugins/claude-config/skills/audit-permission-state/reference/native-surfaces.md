# Native permission surfaces, as this skill relates to them

Four-part records behind the `## Boundary` section in `SKILL.md`. The section carries the
conclusion; this file carries what it rests on. Nothing here asserts that either surface is present
in any session.

## The bundled `fewer-permission-prompts` skill

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `fewer-permission-prompts` is a bundled skill, invocable by the model and the person, not gated | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: true`, `user_invocable: true`, `gated: false`) | 2026-09-29, Claude Code 2.1.284 | A release renames or removes the skill, or changes its invocability |
| It scans transcripts for common read-only Bash and MCP tool calls, then adds a prioritized allowlist to project `.claude/settings.json` | Its commands reference row, <https://code.claude.com/docs/en/commands>, and the same binary extraction's description | 2026-09-29 | The commands page row changes, or a release changes the scope it writes |

## The built-in `/permissions` command

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `/permissions` is a built-in command, user-invocable only, alias `/allowed-tools` | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: false`, `aliases: ["allowed-tools"]`) | 2026-09-29, Claude Code 2.1.284 | A release renames it, changes its alias, or changes its invocability |
| It opens an interactive dialog to view rules by scope, add or remove rules, manage working directories, and review recent auto mode denials | Its commands reference row, <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes |
| Its Auto mode tab views and edits auto mode classifier rules | Same commands row; Claude Code changelog 2.1.246 ("Added an Auto mode tab to `/permissions`") | 2026-09-29 | The commands page row changes or a release removes the tab |
| Recent auto mode denials, with their reasons, appear in the dialog | Claude Code changelog 2.1.193 ("auto-mode denial reasons to ... `/permissions` recent denials") | 2026-09-29 | A release note changes the recent-denials view |
| It lists rules without resolving which wins, and there is no CLI export of the merged set | The Purpose section's own verification record in `SKILL.md` | 2026-09-12 | A release note mentions a permissions export or a merged-outcome view |

## Why the verdict is complementary

Both native surfaces write rules: one derives an allowlist from transcripts, the other edits rules
by hand in a live session. Neither reports the merged outcome across every scope, which scopes
could not be read, or what auto mode drops, and neither runs outside a session. This skill reports
exactly that and writes nothing, so the useful order is to read this report first and then make the
change with the surface that fits.

## Presence

Bundled skills can be removed by `disableBundledSkills` or hidden by `skillOverrides`, and both
surfaces vary by version and host, so the routing reads "when the surface resolves in this session"
and never that it is present. Recheck when a release or docs change adds, removes, or renames a
gating axis.
