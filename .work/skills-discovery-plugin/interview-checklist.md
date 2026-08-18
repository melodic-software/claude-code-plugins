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
- Q6 | answered | round 2 | Adopt native ~/.claude.json skillUsage/pluginUsage as a first-class data source? | yes — hybrid native-first, defensive reads (rec accepted)
- Q7 | answered | round 2 | Fix the skill-usage.jsonl retention gap as part of this work? | yes — extend clean.sh with its own 365-day window (rec accepted)
- Q8 | answered | round 2 | Data-source resolution ladder + coverage labeling? | opportunistic ladder, read all present sources, label coverage in header; cloud loss documented gap (rec accepted)
- Q9 | open | round 3 | Single-operator view only, or must it support teammates on shared repos? (round-2 probe, unanswered — NOT assumed) |
- Q10 | open | round 3 | Skill name / invocation path? |
- Q11 | open | round 3 | Git-churn secondary axis: what corpus and what does it measure? |
- Q12 | open | round 3 | Integration seams: how does it consume inventory, and what changes in observability/discovery? |
- Q13 | open | round 3 | What counts as "cold" — tier definitions and windows? |

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
- [x] Native skillUsage/pluginUsage adoption (Q6) — yes, hybrid native-first
- [x] Retention fix for skill-usage.jsonl (Q7) — yes, own 365d window in clean.sh
- [x] Data-source resolution ladder + coverage labeling (Q8) — opportunistic, labeled
- [ ] Operator scope: single vs multi (Q9)
- [ ] Skill name (Q10)
- [ ] Git-churn dimension detail (Q11)
- [ ] Integration seams w/ inventory, observability, discovery (Q12)
- [ ] Cold-tier definitions and windows (Q13)

## Round-3 grounding facts

- `claude-ops` naming convention: `audit-*` prefix = health/verdict audits (audit-install-state, audit-performance); bare nouns = enumeration/reporting (inventory, observability, morning-brief, plugins, lanes).
- Inventory seam is clean: `python3 ${CLAUDE_PLUGIN_ROOT}/skills/inventory/scripts/inventory.py --out <json>` emits the WHOLE inventory (built-ins, bundled skills, every plugin component); filtering is a presentation concern. Python 3.11+, no third-party deps. This is the denominator source — do not re-enumerate.
- claude-ops plugin.json description enumerates "Ten skills" — adding one requires updating that manifest description and the plugin README (marketplace catalog convention).
- All claude-ops skills carry metadata: workflow-stage (operator/anytime) + cadence (daily/weekly/continuous).

## Session-shorthand glossary

- **heat map** — user's working name for a usage-frequency view over the installed skill fleet: hot = frequently invoked, cold = never invoked.
- **denominator** — the full set of installed skills the usage data is compared against; unused = denominator minus observed invocations.
