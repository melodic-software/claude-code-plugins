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

- Q1 | answered | round 1 | Primary lens: usage telemetry, git churn, or both? | usage primary, churn secondary (rec accepted)
- Q2 | answered | round 1 | Placement: new claude-ops skill, new standalone plugin, or extend observability? | new claude-ops skill (rec accepted)
- Q3 | answered | round 1 | Denominator + aggregation scope? | full installed fleet denominator, cross-repo usage w/ per-repo breakdown (rec accepted; refined by Q8)
- Q4 | answered | round 1 | V1 output shape? | markdown durable + optional HTML heat map (rec accepted)
- Q5 | answered | round 1 | "Why unused" layer? | classification heuristics in V1, proactive nudges deferred (rec accepted)
- Q6 | open | round 2 | Adopt native ~/.claude.json skillUsage/pluginUsage as a first-class data source? |
- Q7 | open | round 2 | Fix the skill-usage.jsonl retention gap (clean.sh coverage) as part of this work? |
- Q8 | open | round 2 | Data-source resolution ladder: which stores does the report read, and how is coverage labeled? |

## Facts resolved (round 1→2 investigation, this environment)

- NATIVE tracking exists: `~/.claude.json` has `skillUsage` (per skill: usageCount, lastUsedAt) and `pluginUsage` (per plugin@marketplace: usageCount, lastUsedAt, lastUsedNumStartups — includes usageCount:0 rows, i.e. a native cold list). Machine-global, aggregate-only (no time series, no per-repo, no tool-vs-typed split), undocumented internal shape.
- skill-usage.jsonl IS custom (bespoke claude-ops store) and IS working — verified live in this container (.claude/observability/skill-usage.jsonl holds this session's planning:interview SkillUse event; git-excluded via .git/info/exclude).
- Default scope is `repo` (.claude/observability under repo root), NOT data-dir; `user` scope = ~/.claude/observability (single cross-repo file, lines carry project_id/branch); `data-dir` scope = ${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>.
- RETENTION GAP: observability clean.sh prunes ONLY hook-events.jsonl + OTEL store; skill-usage.jsonl has no retention and hook::append_jsonl has no rotation. Mitigating: ~250 B/line, growth is slow.
- Cloud caveat: in ephemeral cloud containers both ~/.claude.json and the repo-scope store die with the container — cloud usage data evaporates. Coverage is effectively local-machine.

## Decision tree (`me` mode)

- [x] Primary lens (usage vs churn vs both) — usage primary, churn secondary
- [x] Placement — new claude-ops skill
- [x] Denominator + aggregation scope — full fleet, cross-repo w/ per-repo breakdown
- [x] V1 output shape — markdown + optional HTML heat map
- [x] "Why unused" layer scope — heuristics in V1, nudges deferred
- [ ] Native skillUsage/pluginUsage adoption (Q6)
- [ ] Retention fix for skill-usage.jsonl (Q7)
- [ ] Data-source resolution ladder + coverage labeling (Q8)
- [ ] Skill/command name (blocked by: nothing now — round 3)
- [ ] Git-churn dimension detail (round 3)
- [ ] Integration seams w/ inventory, observability, discovery (round 3)

## Session-shorthand glossary

- **heat map** — user's working name for a usage-frequency view over the installed skill fleet: hot = frequently invoked, cold = never invoked.
- **denominator** — the full set of installed skills the usage data is compared against; unused = denominator minus observed invocations.
