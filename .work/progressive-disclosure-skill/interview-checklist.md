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

- Q1 | open | round 1 | Which plugin homes the skill? |
- Q2 | open | round 1 | What corpus does it audit (load-tier model scope)? |
- Q3 | open | round 1 | Skill name? |
- Q4 | open | round 1 | One skill with one findings taxonomy, or two skills (find-opportunities vs audit-existing)? |
- Q5 | open | round 1 | Read-only classifier vs also applying splits? |
- Q6 | open | round 1 | Deterministic detect.sh fact layer + model judgment split? |
- Q7 | open | round 1 | Threshold philosophy for "too long"? |

## Decision tree (me mode)

- [ ] Plugin home (Q1)
- [ ] Corpus / load-tier scope (Q2)
- [ ] Skill name (Q3, weakly blocked by Q1)
- [ ] One-vs-two skills / action shape (Q4)
- [ ] Mutation posture (Q5)
- [ ] Detection architecture (Q6)
- [ ] Size-threshold philosophy (Q7)
- [ ] Findings taxonomy (shapes + tiers) — round 2, blocked by Q2/Q4
- [ ] Output schema + clean-tree fallback participation — round 2
- [ ] Evals/fixtures scope — round 2
- [ ] Integration deliverables (README/CHANGELOG/version/marketplace tags) — round 2
