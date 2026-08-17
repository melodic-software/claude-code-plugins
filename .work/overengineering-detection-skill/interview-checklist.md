# /planning:interview Checklist — overengineering-detection-skill

Mode: `me` (relentless, user-invoked "/interview me first"). Domain: engineering (new skill/plugin for this marketplace).

## Steps

- [x] Step 1: Survey before you ask
- [x] Step 1.5: Auto-detect — SKIPPED (`me` forces Q&A)
- [ ] Step 2: Drive the frontier-rounds loop (round 2 in flight)
- [ ] Step 3: Stop condition + register gate + confirmation gate
- [ ] Step 4: Persist the contract (PLAN.md Brief) — partial Brief started incrementally
- [ ] Step 5: Hand off

## Session-shorthand glossary

- **enforcement surface** — the union of things that gate, nag, or automate work: Claude Code hooks/guards/standing instructions/skills-as-clutter, git hooks, CI/CD workflow checks, branch protections, GitHub apps and issues automation, external integrations.
- **peel-back / realign** — evidence-gated retirement or simplification of an existing enforcement artifact (the inverse of adding one); "realign" is the user's framing: a course-correction process, not a one-shot fix.
- **#2021 precedent** — this repo's "instruction-economy evidence gate": two guardrails prose-injector guards were config-disabled by default because their evidence didn't earn their standing cost.
- **heat map** — friction/attention signal built from history: where maintenance touches, overrides, suppressions, and failures cluster.
- **rediscovery** — for each artifact, reconstructing the original problem it solved, then re-solving it fresh (native/built-in options first) to see if a simpler solution now exists (tech drift, or it was AI slop from the start).

## Open-question register

- Q1 | answered | round 1 | Audit surface scope | Enforcement surface is V1; code-level product-code lane is a SEPARATE deferred lane (placeholder + follow-up issue); design the core scrutiny method to be lane-reusable
- Q2 | answered | round 1 | Verdict model | Evidence-earned-keep; scrutinize everything; full-context evidence (history, heat maps, friction); reverse-engineer original problem + re-solve simpler; NEVER trust markdown/comments as evidence (claims to verify, not proof); lean simpler/native/built-in unless uncovered use cases; weigh refactoring cost/pain/testing; repeatable self-correcting process
- Q3 | answered | round 1 | Mutation posture | Default = audit/review/report (read-only). Separate explicit action starts the realignment process, which itself drives the SDLC skills (interview/explore/research/plan) with the user — never applied on a whim
- Q4 | answered | round 1 | Fleet scope | Single-repo core; strictly consumer-agnostic per plugin philosophy (no org/repo hardcoding); any upstream-routing (synced/managed files) must be generically detected/declared, presence-gated; fleet coverage via composition
- Q5 | answered | round 1 | V1 cadence | On-demand human-in-the-loop V1; scheduled/daily lane deferred but designed-for (diffable persisted findings enabling delta runs)
- Q6 | answered | round 1 | Research depth | /discovery:research-deep (consensus, authorities) + /discovery:explore over the enforcement surface for real examples, after Brief locks
- Q7 | answered | round 2 | Placement + naming | New plugin `overengineering`; skill-split sub-decision carried to Q7b (user: depends on skill size + best practices; single-purpose skills, composition over inheritance)
- Q7b | open | round 3 | Skill split — two single-purpose skills (`audit` + `realign`) composing via the findings artifact (PLUGIN-ARTIFACT-PROTOCOL seam)? |
- Q8 | answered | round 2 | Neighbor boundaries | Route presence-gated to siblings with documented fallbacks; this plugin owns the cross-surface retirement verdict, never re-implements a sibling's layer
- Q9 | answered | round 2 | Evidence sources + bar | Tiered evidence menu accepted; every verdict cites ≥1 empirical source; doc/comment-only support marked unverified; UNPROVEN verdict for silent artifacts; report must carry everything that drives the reasoning. Output FORMAT split out as Q12
- Q10 | answered | round 2 | Uncertain-intent handling | Include intent-reconstruction checkpoint: ask user when attended + low-confidence; unattended records OPEN-INTENT, never guesses; "I don't know" routes to empirical/ablation track
- Q11 | answered | round 2 | Deferred-lanes mechanics | Follow-up GitHub issues (product-code lane, scheduled/delta lane) via work-items conventions at Brief lock; named in Out-of-scope with links
- Q12 | open | round 3 | Report output format — persisted diffable markdown as source of truth + inline summary + optional presence-gated HTML rendering? |
- Q13 | open | round 3 | Protected categories (unanswered probe from round 2) — security-class artifacts capped at FLAG-FOR-HUMAN, never RETIRE? |

## Decision tree (`me` mode)

- [x] Surface scope (Q1) — enforcement surface V1; product-code lane deferred, method designed lane-reusable
- [x] Verdict/evidence model (Q2) — evidence-earned-keep + scrutinize-everything + rediscovery + cost-weighing
- [x] Mutation posture (Q3) — read-only default; explicit realign action orchestrating SDLC skills with user
- [x] Fleet scope (Q4) — single-repo, consumer-agnostic, generic managed-source detection
- [x] Cadence/autonomy (Q5) — on-demand V1; scheduled deferred, designed-for
- [x] Research depth + pipeline (Q6) — research-deep + explore after Brief
- [x] Placement: new plugin `overengineering` (Q7)
- [ ] Skill split: audit + realign as two single-purpose composing skills (Q7b)
- [x] Neighbor boundaries: presence-gated routing, own the cross-surface verdict (Q8)
- [x] Evidence sources + bar: tiered menu, ≥1 empirical source per verdict, UNPROVEN class (Q9)
- [x] Uncertain-intent / user-checkpoint shape (Q10)
- [x] Deferred-lane mechanics: follow-up issues at Brief lock (Q11)
- [ ] Report output format (Q12)
- [ ] Protected categories / seatbelt list (Q13)
