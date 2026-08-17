# /planning:interview Checklist — overengineering-detection-skill

Mode: `me` (relentless, user-invoked "/interview me first"). Domain: engineering (new skill/plugin for this marketplace).

## Steps

- [x] Step 1: Survey before you ask
- [ ] Step 1.5: Auto-detect — SKIPPED (`me` forces Q&A)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Stop condition + register gate + confirmation gate
- [ ] Step 4: Persist the contract (PLAN.md Brief)
- [ ] Step 5: Hand off

## Session-shorthand glossary

- **enforcement surface** — the union of things that gate or nag work: Claude Code hooks/guards, git hooks, CI/CD workflow checks, branch protections, GitHub apps, external integrations, standing instructions.
- **peel-back** — evidence-gated retirement of an existing enforcement artifact (the inverse of adding one).
- **#2021 precedent** — this repo's "instruction-economy evidence gate": two guardrails prose-injector guards were config-disabled by default because their evidence didn't earn their standing cost.

## Open-question register

- Q1 | open | round 1 | Audit surface scope — full enforcement surface vs Claude-only vs include code-level overengineering? |
- Q2 | open | round 1 | Verdict model — evidence-earned-keep (retirement default) vs advisory complexity report? |
- Q3 | open | round 1 | Mutation posture — read-only audit + separate gated peel action? |
- Q4 | open | round 1 | Fleet scope — single-repo core composing with fleet orchestration, or fleet-native? |
- Q5 | open | round 1 | Automation cadence for V1 — on-demand only vs include scheduled/routine lane? |
- Q6 | open | round 1 | Research depth — /discovery:research-deep consensus pass before planning? |

## Decision tree (`me` mode)

- [ ] Surface scope (Q1)
- [ ] Verdict/evidence model (Q2)
- [ ] Mutation posture (Q3)
- [ ] Fleet scope (Q4)
- [ ] Cadence/autonomy (Q5)
- [ ] Research depth + pipeline (Q6)
- [ ] Placement: new plugin vs skill in existing plugin (blocked by: Q1, Q4)
- [ ] Naming (blocked by: placement)
- [ ] Relationship to neighbors: audit-automation-gaps / audit-instructions / unhobble / plugin-quality:audit (blocked by: Q1, Q2)
- [ ] Evidence sources the verdicts cite (blocked by: Q2)
- [ ] Human-gate shape for retirements (blocked by: Q3)
- [ ] V1 vs deferred lanes (blocked by: Q4, Q5)
