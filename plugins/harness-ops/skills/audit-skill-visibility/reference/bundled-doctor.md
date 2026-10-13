# The bundled `doctor` skill and `/skill-doctor`: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: our decision, the pointer to read live (or the probe that holds the evidence), the date it
was derived, and the event that makes it worth deriving again. The sibling `audit-install-state`
and `audit-performance` skills keep their own records against the `doctor` surface.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| We treat `doctor` (alias `/checkup`) as the native surface that finds unused components against their context cost and offers to fix them, and we never chain into its fixes | [skills: check your setup with /doctor](https://code.claude.com/docs/en/skills#check-your-setup-with-/doctor); the `/doctor` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) | 2026-10-11 | That section changes the unused-components check or its fix behavior |
| Its unused-components check groups unused components, labels each group with a benefit estimate, and applies only the groups the user selects | Probe: string search of the installed 2.1.252 binary (check titled "Check 1: unused skills, MCP servers, and plugins"; estimate text of the form "37 unused skills, saves ~2.2k est. tokens/session") | 2026-08-31 | A release changes the check's grouping, its disable offer, or its estimate |
| We treat `/skill-doctor` as a separate built-in command for per-skill context cost and usage, with its own availability gate read live; the Stats tab carries its report in an interactive session | [skills: find unused skills](https://code.claude.com/docs/en/skills#find-unused-skills); the `/skill-doctor` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands); [changelog 2.1.261](https://code.claude.com/docs/en/changelog#2-1-261) | 2026-10-11 | A later release note names `/skill-doctor`, or it merges into `doctor` |
| We never assume `doctor` is present: it survives the bundled-skill kill switch, but other switches can hide it. Our binary reading on the installed 2.1.263 registers it with `aliases:["checkup"]` and `survivesBundledKillSwitch` | [skills: bundled skills](https://code.claude.com/docs/en/skills#bundled-skills) | 2026-10-11 | That section changes the exemption |
| Neither native surface reconciles more than one source or clamps its window to an observation horizon | Both sections above report unused-versus-cost from the client's own counters; nothing names a JSONL store, OTEL, or a withheld verdict | 2026-10-11 | Either surface gains multi-source reconciliation or an observation-horizon discipline |

## Why the verdict is complementary

Both native surfaces answer "which skills are unused right now, and what do they cost", and
`doctor` offers to disable them. This skill answers the question that follows: which of those are
starved by the listing loop and still wanted, which are unwanted, and which are not observable at
all. It reconciles the native counters with a JSONL store and OTEL, computes an observed horizon,
and withholds every verdict the span cannot support. It is read-only and never disables a skill.

## Presence

`doctor` is the one bundled skill the kill switch leaves typable, but an environment variable or
a `skillOverrides` entry still hides it; `/skill-doctor` is a built-in command with its own gate.
This skill never depends on either and never chains into a `doctor` disable: the audit is complete
on its own, and its description's presence gate names both surfaces only for the question they
own.

## Extraction record

The registry row's observation is a 2026-08-31 targeted string search of the installed 2.1.252
binary, a spot observation over the sibling rows' 2026-08-23 extraction of 2.1.232. This record
re-verifies the `doctor` registration on the installed 2.1.263 binary by string search and reads
the three pages named above, all on 2026-09-11.
