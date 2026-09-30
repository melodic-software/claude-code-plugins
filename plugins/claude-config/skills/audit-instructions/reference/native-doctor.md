# The bundled `doctor` skill, as this skill relates to it

Four-part records behind the `doctor` Boundary section in `SKILL.md`. The section carries the
conclusion; this file carries what it rests on. Nothing here asserts that the surface is present in
any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `doctor` is a bundled skill with alias `checkup`, user-invocable, with model invocation disabled, gated, and it survives `disableBundledSkills` | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: false`, `disable_model_invocation: true`, `gated: true`, `survives_kill_switch: true`, `aliases: ["checkup"]`) | 2026-09-29, Claude Code 2.1.284 | A release renames or removes it, changes its alias, or changes its invocability |
| Its argument hint is `[prompt-audit [<path>]]` | Same binary extraction | 2026-09-29, Claude Code 2.1.284 | A release changes the argument hint |
| `/doctor prompt-audit` (also `/checkup prompt-audit`) audits `CLAUDE.md` files, skills, agents, and commands for prompting patterns written for older models | Claude Code changelog 2.1.283 | 2026-09-29 | A release note changes or removes `prompt-audit` |
| The commands page describes it as auditing `CLAUDE.md` files, skills, and other configuration for outdated or conflicting instructions, instead of running the checkup, and requires v2.1.283 or later | The `/doctor` row of <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes |
| `/doctor` stays typable under `disableBundledSkills`; `DISABLE_DOCTOR_COMMAND` or a `skillOverrides` entry `"doctor": "off"` hides it | <https://code.claude.com/docs/en/skills>, bundled skills section | 2026-09-29 | The skills page changes its gating for `/doctor` |
| Whether `prompt-audit` edits files or only reports is not stated on the commands page or in the changelog; the checkup it replaces reports first and asks before changing anything | The `/doctor` row of the commands page | 2026-09-29 | The commands page or a release note states `prompt-audit`'s write posture |

## Why the verdict is complementary

The vendor pass checks prompting patterns against the current model's guidance. This skill runs a
versioned catalog with target-model scope and citations, checks claims about Claude Code's own
behavior against current docs, and runs a cross-surface conflict pass, and it never edits. Running
both finds more than either; a recurring shape the vendor pass reports belongs in this skill's
catalog as a row, not in a copy of the vendor procedure.
