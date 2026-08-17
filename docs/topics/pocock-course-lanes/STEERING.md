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

## Lane 7 decision rows (closed 2026-08-17)

Interview-first per contract; register gate clean (12/12); user confirmed. Design contract:
`docs/topics/authoring-steering-skill/PLAN.md`. Rows for lane 6's `aihero-course.md` harvest:

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Authoring-time doctrine needs a firing home at the writing moment (L1, L2, L4) | ADOPT | New skill `docs-hygiene:write-for-agents` — model-invoked, write-side complement to the audit siblings; design contract in the topic PLAN.md; built via filed implementation issues |
| Scope = agent-consumed docs (L4) | ADOPT (generalized) | User-widened beyond upstream's skills/AGENTS.md/CLAUDE.md: any agent-consumed markdown in the repo; auto-read surfaces are the high-value core, grounded in a docs-verified enumeration (research artifact in topic memory slice; adapted into the skill's reference) |
| Completion-criteria doctrine (L4) | ADOPT (both moments) | Write-side in the new skill; audit-side as a new `skill-quality:check` criterion so the existing fleet gets graded too |
| Two loads — cognitive load as budget (L1) | ADOPT | Doctrine operates in the skill body; PLUGIN-PHILOSOPHY Instruction economy gains a one-line cross-reference |
| Leading words + negation (L4) | ADOPT | Folded into the skill design; SSOT tracked strand retires when the implementation merges (cross-links the interview-batch-rounds deferral) |
| Pointer wording: cover branches, front-load leading word (L2) | ADOPT (adapted) | Inline in the skill; pointer-quality criteria stay pointed-at in `audit-progressive-disclosure` |
| Trigger enforcement via hook (session-start or otherwise) | REJECT | Probable overengineering (user-decided); trigger reliability instead gated by a shipped plugin-eval suite — positives per trigger family fire, negative controls don't, all-pass gates the implementation PR |
| Vendoring/wrapping upstream `writing-for-agents` | REJECT | Adapted new skill, house doctrine and naming grammar; SSOT decomposition table carries provenance |
| Pruning doctrine (L7) | PARITY — no work | Three pruning tests confirmed covered at parity or stronger (SSOT decomposition table: extract-ssot, audit-derivability, audit-instructions/unhobble) |
| Cross-skill invocation phrasing (upstream `.agents/invocation.md`) | ROUTE | Stays lane 6's candidate (#2904); lane 8 owns invocation doctrine; the new skill's body stays silent on it |

Lane 7 status: decisions closed; implementation issues filed at lane close (see #2909 checklist).
