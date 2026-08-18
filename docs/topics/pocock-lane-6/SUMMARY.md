# Lane 6 summary: vocabulary + provenance consolidation (#2904)

Closed 2026-08-18. The final lane: consolidation, corrections, term verdicts, and the coverage
index that is the effort's "everything is represented" gate.

## Executed (register Q38-Q40)

- **Coverage index** written into the effort contract (`docs/topics/pocock-course-lanes/PLAN.md`):
  per-lesson pointer index over the 49 claim rows (counts verified against the doc), plus the
  outside-the-rows accounting (harness verdict table, quiz-claim handling, machinery exclusions,
  known-open cures, teach-branch status). Q39: pointer shape per the do-not-duplicate rule.
- **SSOT maintenance** (`docs/upstream/mattpocock-skills.md`): row-35 "measured bands" overclaim
  corrected per audit A1; invocation-reach TRACK strand annotated with the landed-unreleased
  evidence (his PRs #878/#880, `.agents/invocation.md`); diagnosing-bugs row annotated with the
  post-mortem-step removal. `docs/upstream/mattpocock-skills-v12-map.md`: private-marketplace
  staleness correction (repo is public; inventory re-verified intact at HEAD `068b6e0`).
- **Term verdicts** recorded in `docs/upstream/aihero-course.md` Lane 6 (seven candidates:
  2 adopt, 1 partial, 1 already-house, 1 rejected-synonym, 1 shorthand-only, 1 no-action).
  Q40 routed through `/domain-driven-design:curate-language`: the repo keeps NO central
  glossary (vocabulary lives in owning plugins' docs), so glossary creation was DEFERRED per
  the lazy-creation rule; the placement question goes to the user, not decided autonomously.
- **Teach-branch check** (Q38): local branch `claude/teach-skill-comparison-h3rpag` holds only
  its interview ledger (commit `49bb9614`), no outcomes; in-flight, pointer-only; the #2904
  guard comment binds its future results to the provenance home.
- `docs/upstream/aihero-course.md` consolidation: trigger discipline and SSOT cross-links were
  verified already present (lane 1's creation was to spec); the Lane 6 section replaces the
  consolidation placeholder.

## Open by design (not blockers)

- Central-glossary creation: user placement choice pending.
- Interactive-session probes: C5 (queueing), C6 and C9-positive second pools.
- The final PR (user go-ahead required) with the contract-slice prune commit.

## Effort totals (lanes 1-6)

49 claim rows + 7 term verdicts; items filed: #2955 #2956 #2957 (lane 1), #2971 #2972 #2973
(lane 2), #2995 (lane 3); lanes 4-6 filed none. Six issues closed: #2899-#2904.
