# /planning:interview Checklist — general-improvement-skill

Topic: a routine-runnable "general improvement" skill for the melodic-software marketplace.
Mode: `me` (relentless, user-invoked). Domain: engineering (build artifact = new skill/plugin in this repo).

## Steps

- [x] Step 1: Survey before you ask — repo scanned; improvement-adjacent lanes identified (architecture:improve, code-tidying:tidy, codebase-health:audit, claude-config:audit-pass, work-items, session-flow:retro, autonomy routines catalog incl. tech-debt-sweep); background Explore agent dispatched for the full landscape map
- [ ] Step 1.5: Auto-detect — SKIPPED (`me` forces Q&A)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Stop condition + register gate + user confirmation
- [ ] Step 4: Persist the contract (PLAN.md Brief, incremental)
- [ ] Step 5: Hand off

## Open-question register

- Q1 | answered | round 1 | Core identity | Hybrid, FINDER-forward (not router-forward): its own judgment about code/product-level improvements; delegation to existing lanes only where it adds value. User skeptical of pure-router value.
- Q2 | answered | round 1 | Default size/impact posture | All sizes, ranked by value-to-effort, lead with highest-impact; prompt/flag narrows.
- Q3 | open | round 1 | Unattended routine mode in V1? | partially: interactive-default confirmed via "start with an interview... feeds into existing workflows"; unattended mode not yet locked — re-asked round 2 as Q3
- Q4 | answered | round 1 | V1 dimensions | REVISED by user: code/product level, performance, config/automation OUTSIDE the codebase (GitHub labels, Actions sync), Claude Code operational setup (cloud env, MCP servers); docs/markdown explicitly OUT (existing lanes own it). Measurement-first: metrics/telemetry is not a fast-follow — "to self-improve you have to measure a baseline"; when data is missing, the improvement IS setting up data capture. App-level observability (e.g. Azure App Insights) as an evidence source.
- Q5 | open | round 1 | Cross-repo scope in V1? | unanswered from round 1 — re-asked round 2
- Q6 | open | round 1 | Apply vs discover-only | implied discover→interview→pipeline handoff; confirm in round 2
- Q7 | open | round 2 | Evidence ladder as the core mechanic (no baseline → instrumentation IS the top recommendation)? |
- Q8 | open | round 2 | V1 evidence sources (repo-native vs external telemetry)? |
- Q9 | open | round 2 | Home + naming (new plugin? noun? skill verb)? |
- Q10 | open | round 2 | Plugin-candidate discovery in V1 or separate? |

## Probe result (round 1)

- No hard requirements declared. New improvement target named: Claude Code cloud environment setup / MCP servers / running CC on web.

## Decision tree (`me` mode)

- [ ] Core identity (router / standalone / hybrid)
- [ ] Default size & ranking posture
- [ ] Interaction model + unattended/routine behavior
- [ ] V1 dimensions in/out (incl. metrics self-improvement, plugin candidates)
- [ ] Cross-repo scope
- [ ] Apply vs discover-only + handoff targets
- [ ] Home + naming (blocked by: core identity)
- [ ] Output artifact shape & persistence (blocked by: interaction model)
- [ ] Routine registration (autonomy catalog? loop? Routine/cron?) (blocked by: interaction model)
- [ ] Prompt interface (vague→specific arg parsing) (blocked by: core identity)

## Explore findings (landscape sweep, round 1 grounding)

- No cross-dimension improvement router exists; `review:fanout` is diff-scoped and refuses whole-repo asks; `claude-config:audit-pass` is config-only; `architecture:improve` is single-lens (deepening) and interview-required.
- No "highest-impact finder" for unfiled opportunities — only `work-items:work` ranks impact, and only over already-filed items.
- `autonomy` routine catalog defines `tech-debt-sweep` (weekly, C1, files sized evidence-backed work items, never mutates, never self-disposes) with NO implementation in the fleet — the new skill could be its implementation.
- Precedents for router shape: `claude-config:audit-pass` (delegate presence-gated, add no criteria), `discipline:sweep-all` (membership via each sibling's own metadata — add a sibling, router picks it up with no edit).
- Overlap governance: reuse-or-replace posture, skill-leaf-name collision registry, mandatory "Skip when"/"NOT for" boundaries, routine catalog incumbent gate.
- Naming constraints: plugin = noun; skill = imperative verb phrase; `improve` leaf owned by `architecture`; bare `audit` is collision bait; verb contract `scan`/`audit` = read-only.
- No plugin scaffolder exists; publishing = plugin.json + marketplace.json entry (./-prefixed source, category from CATALOG-TAXONOMY) + `claude plugin validate --strict` + regenerate CATALOG/cheat-sheet.

## Session-shorthand glossary

- "lanes" — the repo's existing specialized skill families (tidy lane, audit lanes, work-items lane, etc.)
- "router" — a skill that surveys + delegates to installed specialized skills presence-gated, in the style of claude-config:audit-pass
