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

- Q1 | answered | round 1 | Primary target ecosystems for V1? | ecosystem-adaptive; first-class .NET/C#, TS/JS, Python, shell; others degrade to grep fallback
- Q2 | answered | round 1 | Home & name? | new skill `audit-dead-code` inside the existing code-tidying plugin
- Q3 | answered | round 1 | Scope of "dead" for V1? | unreferenced code symbols + orphaned files; deps/config/assets/flags deferred to V2
- Q4 | answered | round 1 | Output posture? | report-only, removal delegated to /tidy, /simplify, work-items
- Q5 | answered | round 1 | Detection strategy? | tool-first, model-verified; grep fallback where no tool exists; every finding survives a verification pass
- Q6 | open | round 2 | Verdict vocabulary / confidence tiers? |
- Q7 | open | round 2 | Suppression write-back — apply, propose, or omit? |
- Q8 | open | round 2 | Missing-tool behavior — never install, degrade, or prompt? |
- Q9 | open | round 2 | Scan scope — whole repo, path arg, or tidy-lane reuse? |
- Q10 | open | round 2 | Findings persistence — stdout, persisted file, work-items handoff? |
- Q11 | open | round 2 | Setup skill / project config, or zero-config V1? |
- Q12 | open | round 2 | Eval fixture strategy for the skill? |

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

- [done] External research: per-ecosystem dead-code detection tool landscape → `research-tool-landscape.md`. Headlines: knip is the sole live TS/JS tool (ts-prune/depcheck/unimported archived); vulture+deptry+ruff for Python; Roslyn IDE0051/52 + `jb inspectcode` (SARIF) for .NET; shellcheck SC2034/SC2317 is weak by design (model pass carries shell); staticcheck U1000 + x/tools deadcode for Go; rustc dead_code + cargo-machete for Rust. All recommended tools except vulture/shellcheck-text emit JSON or SARIF. Strong LLM prior art for tool→LLM-verifier architecture (Datadog, LLM4PFA, QASecClaw). Cross-cutting FP classes: reflection, string-keyed dispatch/DI, framework entry points, dynamic imports, external/cross-language consumers, codegen, feature-gated code. Verdict shape suggestion: dead/alive/uncertain, "alive" cites evidence and writes back into the tool's native suppression mechanism so reruns converge.
