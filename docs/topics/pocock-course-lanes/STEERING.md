# pocock-course-lanes — steering-section addendum

Extends the six-lane contract in `PLAN.md` (branch `claude/plan-mode-discussion-55kszx`,
unmerged when this was written) with the course's **Steering** section: nine lessons pasted and
inventoried in the 2026-08-17 steering-section session (branch
`claude/pocock-steering-course-00zkvd`). Same contract rules apply: interview-first per lane,
claim ladder, lanes discuss and decide but do not implement, decision rows land in
`docs/upstream/aihero-course.md` (lane 6's deliverable), coverage index closes in lane 6.

**PLAN.md amendment pending:** its Goal/acceptance say "six lanes"; when the contract branch
merges, extend the lane index with lanes 7–9 below and re-scope lane 6's coverage index to
include the nine steering lessons.

## Session outcome (2026-08-17)

The session re-evaluated the SSOT's `writing-for-agents` rejection and superseded it: parity
holds only for the pruning/audit half. Full section-by-section verdicts:
`docs/upstream/mattpocock-skills.md` → "writing-for-agents decomposition". Corrections landed
in this session; substance rides the lane issues.

Interview decisions (user-confirmed):

- **Authoring-time doctrine** → a NEW authoring skill (adapted, not vendored/wrapped), with
  trigger reliability as a first-class design constraint (user concern: the skill only helps
  if it fires at the writing moment; hook-forced loading judged probable overengineering).
- **Invocation-mode posture** → evidence-driven rubric; neither upstream's user-invoked
  default nor our model-invoked default assumed correct.
- **Tracking** → issues filed per lane (below); mapping-doc correction done in-session.
- **Terminology** ("sediment", "cache", "push/point", "context load", "navigation pointer",
  "cognitive load") → candidates handed to lane 6 (#2904) term adoption, not decided here.

## Steering lane index (filed 2026-08-17)

| Lane | Issue | Scope | Lessons covered |
|------|-------|-------|-----------------|
| 7 authoring doctrine | [#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909) | new authoring skill; context-pointer wording, information hierarchy, completion criteria, two loads, leading words + negation | 1, 2, 4 (authoring half), 7 (parity rows) |
| 8 invocation mode | [#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910) | invocation rubric, setup-convention doc, 17 missing keys, router pattern, invocation-reach invariant, fleet re-grade (ADR 0005-bounded) | 3, 4 (invocation half), 5 (incl. cloud-scope caveat) |
| 9 steering validations | [#2911](https://github.com/melodic-software/claude-code-plugins/issues/2911) | claude-memory:audit nav-pointer criteria, design-smell caveat, auto-memory parity, /init-then-prune eval fixture, steering harness-claims bundle | 6, 8, 9 + leftovers of 1–2 |

Lesson key: 1 The Steering Map · 2 Steering With A Pointer · 3 What Are Agent Skills ·
4 Write A Skill · 5 User Vs Project Skills · 6 Navigation Pointers · 7 Pruning ·
8 Trying Out Pruning · 9 Claude Code's Automatic Memory.

Suggested run order: 7 → 8 → 9 (impact order; 7 and 8 both feed lane 6's harvest, so all three
should close before lane 6 does).
