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

## Plan

*(empty — `/planning:plan` fills this after the Brief locks)*
