# pocock-course-lanes

Brief locked via `/planning:interview me` (rounds 1–3, all nine questions decided; register
gated clean). The working ledger lives in the topic's memory slice
(`.work/pocock-course-lanes/`, disposable per session — this committed file is the durable
record).

## Brief

### TLDR

Vet the AI Hero course lessons (plan mode, grilling, compaction, handoff, phase boundaries,
auto-compaction) against this marketplace's plugins in six independent lanes — each lane
interview-first with our own skills, each ending in recorded adopt/reject/track decisions, filed
work items for any plugin change, and a lane summary. Source material is course content — a
distinct source from the already-audited mattpocock/skills repo (SSOT current at v1.2.3
`@84fdeff`).

### Goal

Every opinionated claim in the five pasted lessons is *represented*: mapped to a decision row, a
filed work item, or an explicit not-relevant note — nothing silently dropped. The lanes:

1. **plan-mode/asset-rush** — his plan-mode critique vs our interview→plan sequencing; audit
   whether `lock` / auto-synthesize is a licensed exception or a quiet re-introduction of the
   asset rush.
2. **grilling↔interview parity** — course-lesson deltas against `planning:interview` (expected
   mostly confirmation; small tree).
3. **compaction doctrine** (merges the Compaction + Auto-Compaction lessons) —
   fork-beats-compaction vs his compact-as-default; the `context-guard` evidence-degraded marker
   vs his steered-compact-for-QA case; auto-compact stance; `autoCompactWindow` and
   compaction-mechanics claims verified against official docs.
4. **handoff** — his 15-line skill vs our save-point engine; the purpose-argument adoption
   candidate; handoff-file expiry/accumulation; ephemerality philosophy (OS temp vs memory
   tier). **Use-case boundary evaluation** (user, round 3): our dominant real use is a hard
   session-chain handoff — dumb-zone escape → session-ID chain → whole-picture reconstruction
   for retrospectives; functionally a compact-replacement that regathers — while his taxonomy
   centers on crossing boundaries (other agent, other repo, colleague, forked side task).
   Decide which use cases our handoff officially owns, which route elsewhere, and whether the
   session-chain/retrospective use deserves first-class support.
5. **phase-boundaries decision tree** — element-by-element re-audit of the
   `session-flow:workflow` continuation router against the *course* version of his tree (the
   SSOT audited repo `PHASE-BOUNDARIES.md`, not this lesson); includes subagent-not-a-terminal
   and the AFK criterion.
6. **shared vocabulary + provenance** — which dictionary terms (smart zone, primary/secondary
   source, AFK, design concept, phase boundary) we adopt as ubiquitous language; establishes
   `docs/upstream/aihero-course.md`. Runs last; harvests from all other lanes.

### Constraints

- **Interview-first per lane**: each lane opens with `/planning:interview me <lane>`, using
  marketplace skills throughout (`discovery:explore` / `discovery:research`,
  `planning:brainstorm`, discipline skills as fits).
- **Claim ladder** (vetting standard): (i) harness-behavior claims → verified live against
  current official docs before being repeated or acted on; (ii) empirical quality claims →
  classified folklore-vs-measured, `context-guard`'s measured bands as baseline, his figures
  recorded as anchors never adopted as numbers; (iii) design opinions → decided
  adopt/reject/track against our plugin philosophy, never "verified" by research.
- **Lanes discuss and decide; they do not implement.** Plugin changes leave the lane as filed
  work items and execute via the normal implementation pipeline.
- **Cloud durability**: decisions are promoted into committed-and-pushed artifacts (this file,
  the provenance doc, tracker items) the moment they lock; `.work/` is a per-session cache and
  is never load-bearing.

### Acceptance criteria

- Six lanes each closed with the three fixed outputs: adopt/reject-with-reason/track-on-event
  rows in `docs/upstream/aihero-course.md`, work items filed for every decided plugin change,
  and a lane summary in the lane's topic slice.
- A coverage index in this topic maps every lesson claim to its disposition (decision row /
  filed item / not-relevant note).
- `docs/upstream/aihero-course.md` exists with its own recheck-trigger discipline
  (lesson-updated, not release-named) and is cross-linked from
  `docs/upstream/mattpocock-skills.md`.

### Captured assumptions

- Discussions are user+Claude working sessions; no external participants — hence topic dirs +
  tracker items rather than GitHub Discussions. (Round 1 probe drew no contrary constraint;
  flip to Discussions if that changes.)

### Out-of-scope

- Executing plugin changes inside a lane session.
- Re-auditing the mattpocock/skills repo itself (SSOT current; recheck trigger unchanged).

### Decided in rounds 2–3 (previously deferred)

- Q6 — lane order: handoff → phase-boundaries → compaction → plan-mode → grilling →
  vocabulary/provenance.
- Q7 — dispatch: one background `/discovery:research` for the harness-claims bundle
  (`autoCompactWindow`, compaction mechanics, plan-mode behavior — verified against current
  official docs); `/discovery:explore` and `/planning:brainstorm` fire per lane at open;
  nothing else speculative. (The pre-lane inventory recheck already ran — see below.)
- Q8 — durability: git + GitHub are the only durable spine; `.work/` never load-bearing;
  every session ends with clean-stop semantics (commit + push + issue updates), never a
  machine-local handoff file; one GitHub issue per lane; contract branch PRs when locked,
  then one branch + PR per lane.
- Q9 — decision-matrix skill: evolve `session-flow:workflow`'s `continue` router (no new
  skill) to consume session history, the overarching plan, work-item state, and the
  context-guard zone; **suggest-by-default, autonomous only as an explicit opt-in**, designed
  around instruction-audit check I23 (no exit menus injected into model context). This is
  lane 5's build deliverable.

### Deferred questions

*(none — all nine questions decided)*

## Lane index (filed 2026-08-17, in locked run order)

| Lane | Issue | Scope |
|------|-------|-------|
| 1 handoff | [#2899](https://github.com/melodic-software/claude-code-plugins/issues/2899) | use-case boundaries, purpose argument, expiry, ephemerality |
| 2 phase boundaries | [#2900](https://github.com/melodic-software/claude-code-plugins/issues/2900) | tree re-audit + context-driven continuation router (build deliverable) |
| 3 compaction doctrine | [#2901](https://github.com/melodic-software/claude-code-plugins/issues/2901) | fork-beats-compaction, auto-compact stance, evidence-degraded marker, harness claims |
| 4 plan-mode | [#2902](https://github.com/melodic-software/claude-code-plugins/issues/2902) | asset-rush critique vs interview-first sequencing, lock-mode audit |
| 5 grilling parity | [#2903](https://github.com/melodic-software/claude-code-plugins/issues/2903) | course-lesson deltas vs planning:interview |
| 6 vocabulary + provenance | [#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904) | aihero-course.md, term adoption, SSOT TRACK annotations, coverage index |

Background research dispatched pre-lane: harness-claims bundle →
`.work/pocock-course-lanes/harness-claims/` (memory tier; re-dispatch `/discovery:research` if
the slice is gone before lane 3/4 consume it).

## Upstream recheck — 2026-08-17 (pre-lane gate)

`/discipline:recheck-against-upstream` run against mattpocock/skills HEAD `068b6e0`
(2026-08-15) from the audited baseline v1.2.3 `@84fdeff`; shallow clone at
`/workspace/mattpocock/skills` (session-local, disposable). Findings:

- **Inventory intact**: 35 skills, zero additions/removals/renames — the v1.2 map's
  his↔ours rows are structurally accurate; grilling→`planning:interview`,
  handoff→`session-flow:handoff`, phase-boundaries→`session-flow:workflow continue`
  mappings all confirmed.
- **No new release**: latest tag is still v1.2.3, so the SSOT's release-based recheck
  triggers have NOT fired; all drift below is unreleased main.
- **Invocation-reach invariant hardened** (PRs #878/#880, `.agents/invocation.md`):
  cross-skill dependencies standardized on "Call the Skill tool with \"name\"" (one skill
  per call; his stated reason: higher hit rate than bare `/name` prose, harness-neutral);
  user-invoked skills declared unreachable from any skill — preconditions on them must be
  phrased "tell the user to run /x". This is the SSOT's *tracked* writing-for-agents
  strand: substance has landed on main with changesets, release pending — the tracked
  row's trigger will fire on the next release. Portable authoring question for OUR skills
  (cross-skill invocation phrasing) → lane 6 candidate.
- **`diagnosing-bugs` dropped its post-mortem step** (Phase 6 "Cleanup + post-mortem" →
  "Cleanup"; the "what would have prevented this bug → improve-codebase-architecture"
  handoff removed). Relevant to the SSOT's diagnosing-bugs TRACK row when its release
  trigger fires.
- **Rest of the diff**: em-dash/phrasing cosmetics (grilling #879, others) — no delta to
  our derived skills.
- **Skipped**: nothing — every changed file since baseline was inspected (15 skill files +
  `.agents/invocation.md`).

Verdict: our map and SSOT audit clean at their recorded baseline; no doc corrections
required now. Annotating the two TRACK rows with the landed-but-unreleased evidence is
lane-6 bookkeeping.

## Plan

*(empty — `/planning:plan` fills this after the Brief locks)*
