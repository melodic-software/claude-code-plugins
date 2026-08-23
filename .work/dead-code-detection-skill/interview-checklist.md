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
- Q6 | answered | round 2 | Verdict vocabulary / confidence tiers? | three verdicts: `dead` (T1) / `uncertain` (T2) / `alive` (T3, reported with saving evidence, not work) — carried in the flat record protocol
- Q7 | answered | round 2 | Suppression write-back? | propose, never apply — report emits ready-to-paste native suppression entries per tool; read-only guarantee preserved
- Q8 | answered | round 2 | Missing-tool behavior? | never auto-install; detect presence, label which detectors ran/skipped, grep fallback marked reduced-confidence; partial sweep must never read as complete
- Q9 | answered | round 2 | Scan scope? | whole-repo default + optional path/glob arg; reuse `.claude/tidy-lanes/` globs as named scopes when present, never inherit lane rotation
- Q10 | answered | round 2 | Findings persistence? | markdown to stdout + persisted findings file in `.work/` slice + opt-in `work-items:track` handoff
- Q11 | answered | round 2 | Setup skill / config? | zero-config V1, no setup skill; suppression lives in each tool's own native config
- Q12 | answered | round 2 | Eval fixture strategy? | per-ecosystem fixtures each pairing a known-dead symbol with a known-alive-via-dynamic-reference trap (DI registration, getattr, string dispatch); plus detect.test.sh unit suite

## Decision tree (`me` mode)

- [ ] Intake: target ecosystems / where this will actually run (Q1)
- [ ] Home & name (Q2)
- [ ] Scope of "dead" for V1 (Q3)
- [ ] Output posture: report-only vs --fix (Q4)
- [ ] Detection strategy: tool-first vs model-first (Q5)
- [x] Confidence-tier model (Q6) — dead / uncertain / alive
- [x] Findings persistence / work-items handoff (Q10) — stdout + .work file + opt-in track
- [x] Verification discipline (Q5, Q6) — every candidate adjudicated; `alive` cites saving evidence
- [x] Per-ecosystem tool roster + fallback (Q1, Q8) — knip / vulture / Roslyn+inspectcode / shellcheck; grep fallback, never auto-install
- [x] Suppression write-back posture (Q7) — propose-only
- [x] Scan scope (Q9) — whole-repo default, optional path/glob, tidy-lane globs as named scopes
- [x] Setup skill / project config (Q11) — zero-config V1
- [x] Composition contract with tidy/simplify/work-items (Q2, Q4, Q10)
- [x] Evals plan (Q12) — paired dead/alive-trap fixtures per ecosystem + unit suite
- [x] Acceptance criteria for V1 — written into the Brief (Step 4)

## Deferred (recorded in the Brief)

- Q13 | deferred | round 2 | V2: add unused-dependency reporting first? | after V1 ships — Brief Deferred questions, arbiter USER-RESERVED
- Q14 | deferred | round 2 | Does a known-alive/entry-point config become necessary? | after V1 FP data — Brief Deferred questions, arbiter USER-RESERVED

## Session-shorthand glossary

- "tool-first" — run ecosystem-native dead-code detectors (e.g. knip, vulture) and treat their output as candidates; the model adjudicates, it does not re-derive reachability
- "delegated removal" — the skill reports findings but never edits; deletion is handed to /tidy, /simplify, or an explicit --fix path

## Background lookups

- [done] External research: per-ecosystem dead-code detection tool landscape → `research-tool-landscape.md`. Headlines: knip is the sole live TS/JS tool (ts-prune/depcheck/unimported archived); vulture+deptry+ruff for Python; Roslyn IDE0051/52 + `jb inspectcode` (SARIF) for .NET; shellcheck SC2034/SC2317 is weak by design (model pass carries shell); staticcheck U1000 + x/tools deadcode for Go; rustc dead_code + cargo-machete for Rust. All recommended tools except vulture/shellcheck-text emit JSON or SARIF. Strong LLM prior art for tool→LLM-verifier architecture (Datadog, LLM4PFA, QASecClaw). Cross-cutting FP classes: reflection, string-keyed dispatch/DI, framework entry points, dynamic imports, external/cross-language consumers, codegen, feature-gated code. Verdict shape suggestion: dead/alive/uncertain, "alive" cites evidence and writes back into the tool's native suppression mechanism so reruns converge.
