# /planning:interview Checklist — docs-hygiene-audit-noise

Topic: repo-wide `/docs-hygiene:audit-noise` orchestrated run + skill fallback update.

## Steps

- [x] Step 1: Survey before you ask — repo has 1131 tracked `.md` (1027 after excluding evals fixtures + changelogs); tree clean; skill's literal default is a no-op on clean tree; detect.sh serial run over full corpus exceeds 5 min (needs chunking); `/session-flow:orchestrate` armed; user clarified intent mid-turn (orchestrated full-repo run + skill fallback design)
- [ ] Step 1.5: Auto-detect — user asked to be interviewed; forced Q&A (`me`-leaning)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Recognize the stop condition
- [ ] Step 4: Persist the contract
- [ ] Step 5: Hand off

## Open-question register

- Q1 | open | round 1 | Deliverable: report-only, or report + apply Tier 1 treatments in this session? |
- Q2 | open | round 1 | Corpus scope/exclusions for the repo-wide run? |
- Q3 | open | round 1 | Where does the audit report land (committed memory slice vs PR-only vs artifact)? |
- Q4 | open | round 1 | Orchestration shape: concurrency cap, model tier, verification pass? |
- Q5 | open | round 1 | Skill update scope: audit-noise fallback only, or propagate to sibling audit skills? |
- Q6 | open | round 1 | File the rate-limit-telemetry enhancement issue now, or defer? |

## Decision tree (`me` mode)

- [ ] Deliverable shape (Q1)
- [ ] Corpus scope (Q2)
- [ ] Report destination (Q3)
- [ ] Orchestration parameters (Q4)
- [ ] Skill fallback update scope (Q5)
- [ ] Rate-limit telemetry issue (Q6)

## Session-shorthand glossary

- "fallback" — the behavior `/docs-hygiene:audit-noise` should adopt when invoked with no target AND a clean tree (today: friendly no-op)
- "slices" — topic-docs working directories: `docs/topics/<slug>/` (contract tier) and `.work/<slug>/` (memory tier)
