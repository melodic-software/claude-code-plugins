# /planning:interview Checklist — progressive-disclosure-skill

## Steps

- [x] Step 1: Survey before you ask — repo surveyed: docs-hygiene audit-* family (audit-noise, audit-derivability, audit-encapsulation), skill-quality static gates, playbooks:skill-authoring (hub/spoke doctrine), shared clean-tree-fallback contract, marketplace/plugin manifests
- [x] Step 1.5: Auto-detect — user explicitly requested interview; Q&A loop engaged (me-leaning)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Recognize the stop condition (register gate + user confirmation)
- [ ] Step 4: Persist the contract (PLAN.md Brief — engineering session)
- [ ] Step 5: Hand off

## Session-shorthand glossary

- **load tier** — when a file's content enters an agent's context: always-loaded (CLAUDE.md, unscoped rules, skill descriptions in the listing), invocation-loaded (SKILL.md body, agent/command body on trigger), on-demand (context/, reference/, docs read only when pointed to)
- **hub/spoke** — progressive-disclosure structure: a small always-or-invocation-loaded hub carrying pointers ("context clues") to on-demand spoke files

## Open-question register

- Q1 | answered | round 1 | Which plugin homes the skill? | docs-hygiene
- Q2 | answered | round 1 | What corpus does it audit (load-tier model scope)? | all agent-facing instruction surfaces, load-tier model (always-loaded / invocation-loaded / on-demand)
- Q3 | answered | round 1 | Skill name? | audit-progressive-disclosure — user: explicit over implicit; "disclosure" alone is ambiguous; no per-type actions planned
- Q4 | answered | round 1 | One skill or two? | one skill, one findings taxonomy (both concerns = one audit over the load-tier model)
- Q5 | answered | round 1 | Read-only vs applying splits? | read-only v1; treatment guidance per finding; split action deferred until demand
- Q6 | answered | round 1 | Deterministic detect.sh + model judgment? | yes — script emits facts (sizes, heading census, tier classification, pointer inventory); model owns concern-mixing/relevance judgment
- Q7 | answered | round 1 | Threshold philosophy? | advisory, tier-calibrated signals; never hard gates; concrete defaults grounded in upstream guidance during authoring, repo-overridable
- Q8 | open | round 1 probe | Non-markdown surfaces (MCP tool descriptions, hook configs) in scope? |
- Q9 | open | round 1 probe | Must it work in non-Claude-configured repos (plain docs repos)? |

## Directives

- User: ground the skill in deep research on progressive disclosure — consensus-based, official/authoritative/trusted sources, latest information; definitely include Anthropic's prescribed view. → dispatched to /discovery:research (results land in this slice as RESEARCH.md)

## Decision tree (me mode)

- [x] Plugin home (Q1) — docs-hygiene
- [x] Corpus / load-tier scope (Q2) — agent-facing instruction surfaces, load-tier model
- [x] Skill name (Q3) — audit-progressive-disclosure
- [x] One-vs-two skills / action shape (Q4) — one skill, one taxonomy
- [x] Mutation posture (Q5) — read-only v1
- [x] Detection architecture (Q6) — detect.sh facts + model judgment
- [x] Size-threshold philosophy (Q7) — advisory, tier-calibrated
- [ ] Non-markdown surfaces in scope (Q8)
- [ ] Non-Claude repos supported (Q9)
- [ ] Findings taxonomy (shapes + tiers) — round 2, blocked by research
- [ ] Output schema + clean-tree fallback participation — round 2
- [ ] Evals/fixtures scope — round 2
- [ ] Integration deliverables (README/CHANGELOG/version/marketplace tags) — round 2
