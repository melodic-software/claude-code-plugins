# pocock-course-lanes

Interview in progress (`/planning:interview me`, round 2 open). This Brief persists locked
decisions incrementally so a cloud-session loss never discards resolved branches; the working
ledger lives in the topic's memory slice (`.work/pocock-course-lanes/`, disposable per session).

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
   tier).
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

### Deferred questions

- Q6 (arbiter: USER-RESERVED) — lane ordering / priority.
- Q7 (arbiter: USER-RESERVED) — dispatch model: which explore/research runs fire now in
  background vs at lane open.
- Q8 (arbiter: USER-RESERVED) — per-session management + durability mechanics (end-of-session
  ritual, branch policy for lane docs).

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
