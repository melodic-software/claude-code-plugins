# /planning:interview Checklist — skills-discovery-plugin

Topic: skills discovery / heat map capability (which skills are used vs unused, and why).
Mode: `me` (relentless) — user asked for an interview session. Domain: engineering.

## Steps

- [x] Step 1: Survey before you ask — grounded: skill-usage-audit telemetry (two producers: PostToolUse/Skill `tool` + UserPromptExpansion `expansion`), bespoke store `${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>/skill-usage.jsonl` (claude-ops), hook-telemetry sink convention, observability skill (reads OTEL/hook-events/ccusage — does NOT read skill-usage), inventory skill (enumerates all skills = denominator), discovery plugin (explore/research/blindspot — different sense of "discovery"). No prior topic slice under docs/topics/ or .work/.
- [ ] Step 1.5: Auto-detect — SKIPPED (`me` forced by user's "interview session" request)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Stop condition — register grades clean + user confirms restated understanding
- [ ] Step 4: Persist the contract — PLAN.md Brief at docs/topics/skills-discovery-plugin/PLAN.md
- [ ] Step 5: Hand off

## Open-question register

- Q1 | open | round 1 | Primary lens: usage telemetry, git churn, or both? |
- Q2 | open | round 1 | Placement: new claude-ops skill, new standalone plugin, or extend observability? |
- Q3 | open | round 1 | Denominator + aggregation scope: which skills counted, per-repo or cross-repo usage? |
- Q4 | open | round 1 | V1 output shape: markdown report, HTML heat map, or both? |
- Q5 | open | round 1 | "Why unused" layer: classification heuristics in V1, proactive nudges deferred? |

## Decision tree (`me` mode)

- [ ] Primary lens (usage vs churn vs both)
- [ ] Placement (claude-ops skill / new plugin / extend observability)
- [ ] Denominator + aggregation scope
- [ ] V1 output shape
- [ ] "Why unused" layer scope (heuristics vs nudges)
- [ ] Skill/command name (blocked by: placement)
- [ ] Git-churn dimension detail (blocked by: primary lens)
- [ ] Integration seams w/ inventory, observability, discovery (blocked by: placement)
- [ ] Data-gap handling: sessions/repos where the hook never ran (blocked by: denominator scope)

## Session-shorthand glossary

- **heat map** — user's working name for a usage-frequency view over the installed skill fleet: hot = frequently invoked, cold = never invoked.
- **denominator** — the full set of installed skills the usage data is compared against; unused = denominator minus observed invocations.
