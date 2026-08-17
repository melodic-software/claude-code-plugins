# /planning:interview Checklist — dead-code-detection-skill

Topic: dedicated dead-code detection skill for the melodic-software marketplace.
Mode: `me` (relentless). Domain: engineering (new skill/plugin component in this repo).

## Steps

- [x] Step 1: Survey before you ask — prior-session coverage survey (tidy Beck #2, simplify/batch-simplify diff-scoped, architecture:improve verification discipline, linter hooks); repo conventions read (AGENTS.md, code-tidying plugin.json, docs/topics + .work slices)
- [ ] Step 1.5: Auto-detect — SKIPPED (`me` forces Q&A)
- [ ] Step 2: Drive the frontier-rounds loop
- [ ] Step 3: Stop condition — register grades clean + user confirms restated understanding
- [ ] Step 4: Persist the contract — PLAN.md Brief at docs/topics/dead-code-detection-skill/
- [ ] Step 5: Hand off — recommend next pipeline step + session config

## Open-question register

- Q1 | open | round 1 | Primary target ecosystems the skill must serve in V1? |
- Q2 | open | round 1 | Home & name — new skill inside code-tidying, or elsewhere? |
- Q3 | open | round 1 | Scope of "dead" for V1 — code-only, or also deps/config/assets/flags? |
- Q4 | open | round 1 | Output posture — report-only with delegated removal, or detect+fix? |
- Q5 | open | round 1 | Detection strategy — tool-first with model verification pass, or model-first? |

## Decision tree (`me` mode)

- [ ] Intake: target ecosystems / where this will actually run (Q1)
- [ ] Home & name (Q2)
- [ ] Scope of "dead" for V1 (Q3)
- [ ] Output posture: report-only vs --fix (Q4)
- [ ] Detection strategy: tool-first vs model-first (Q5)
- [ ] Confidence-tier model (blocked by: Q4)
- [ ] Findings persistence / work-items handoff (blocked by: Q4)
- [ ] Verification discipline — what every finding must pass before report (blocked by: Q5)
- [ ] Per-ecosystem tool roster + fallback when no tool exists (blocked by: Q1, Q5)
- [ ] Setup skill / project config (lanes-style) or zero-config (blocked by: Q2, Q1)
- [ ] Composition contract with tidy/simplify/work-items (blocked by: Q2, Q4)
- [ ] Evals plan for the skill (blocked by: most of the above)
- [ ] Acceptance criteria for V1 (blocked by: all of the above)

## Session-shorthand glossary

- "tool-first" — run ecosystem-native dead-code detectors (e.g. knip, vulture) and treat their output as candidates; the model adjudicates, it does not re-derive reachability
- "delegated removal" — the skill reports findings but never edits; deletion is handed to /tidy, /simplify, or an explicit --fix path

## Background lookups

- [dispatched] External research: per-ecosystem dead-code detection tool landscape (TS/JS, Python, .NET, shell, Go, Rust) — feeds the tool-roster branch
