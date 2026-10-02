# The bundled `explain-usage` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. Nothing here asserts the skill is present in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `explain-usage` is a bundled skill: "Explain where this session's tokens went, with one simple chart in plain language", menu line "See where this session's tokens went, in plain words" | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29 (`bundled_skills` lane) | 2026-09-29 | A release renames or removes the skill, or changes its description |
| It is model-invocable and user-invocable, takes no argument hint, and is gated | The same extraction (`model_invocable`, `user_invocable`, `gated` all true) | 2026-09-29 | A release changes its invocability or its gate |
| It is undocumented on the commands page and no changelog entry names it, so the extraction is the only basis | <https://code.claude.com/docs/en/commands> and <https://code.claude.com/docs/en/changelog> read for the name | 2026-09-29 | The commands page gains an `/explain-usage` row, or a release note names it |
| Its scope is the current session; nothing in its description reads other sessions, hook data, cost, or local telemetry stores | The description above | 2026-09-29 | A release widens its description past this session's tokens |
| Its description names an explanation and a chart, not a file write | The description above | 2026-09-29 | A release gives it an output file or a fix action |

## Why the verdict is complementary

Both answer questions about token use. `explain-usage` explains one session, the current one, in
plain words from the harness's own accounting. This skill reads what the machine captured locally
(OTEL store, hook event log, ccusage) and reports across sessions: trends, cost, hook latency, and
what each hook did. A person asking "where did this session's tokens go" is better served by the
native explanation where it resolves; everything cross-session or hook-related stays here.

## Presence

Bundled skills can be removed by `disableBundledSkills`, hidden by a `skillOverrides` entry, and
vary by plan, platform, and host (<https://code.claude.com/docs/en/skills>, bundled skills section,
read 2026-09-29). The routing reads "resolves in this session", never "is available". Recheck when
a release or docs change adds, removes, or renames a gating axis.
