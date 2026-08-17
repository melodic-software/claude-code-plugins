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

- Q1 | open | round 1 | Core identity: orchestrating router over existing improvement lanes vs standalone finder? |
- Q2 | open | round 1 | Default size/impact posture (small/medium/large)? |
- Q3 | open | round 1 | Interaction model: interactive discussion vs unattended routine output — one skill, both modes? |
- Q4 | open | round 1 | V1 improvement dimensions (code, docs, config, plugin/skill quality, metrics-driven self-improvement, plugin-candidate discovery)? |
- Q5 | open | round 1 | Cross-repo scope in V1? |
- Q6 | open | round 1 | Does it ever APPLY improvements, or discovery/deliberation only? |

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
