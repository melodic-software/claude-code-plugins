# Lane 4 summary: plan mode / asset rush (#2902)

Closed 2026-08-17. Vetted the "Why Plan Mode Sucks" lesson (source committed at
`docs/topics/pocock-course-lanes/lessons/04-why-plan-mode-sucks.md`) against the planning
pipeline: `planning:interview` (pre-clarity contract, auto-detect, auto-guard, `lock`
STOP-on-gap, general-domain terminal) and `planning:plan` (approval gate, Open Decisions before
the plan body, devils-advocate dispatch, decision confidence gate). Verdicts C7-C9 graded the
walkthrough claims.

## Decisions (register Q31-Q35, provenance: user's restated acceptance, "Go with your recommendations")

- **Q31 asset-rush critique: ADOPTED (convergent).** The critique is the design rationale the
  pipeline embodies twice over: the Brief locks intent before planning, and the plan skill
  itself refuses inline decision-locking (Open Decisions block, confidence gate routing judgment
  calls back to interview rounds, user approval before any code). Plan mode is repositioned as a
  permission gate, never the alignment mechanism.
- **Q32 lock-mode audit: LICENSED EXCEPTION.** The auto-guard bars synthesizing genuine user
  decisions; `lock` is user-invoked (invocation IS the confirmation) with STOP-on-gap; the
  default action leans to relentless `me`; `/planning:audit-answers` is the producer-not-critic
  compensating control, exercised live in this very effort (it corrected two contract
  decisions). No change filed.
- **Q33 design concept: already embodied.** The general-domain interview terminal (shared
  understanding, no artifact, no handoff) is the design-concept endpoint; the term maps to our
  "shared understanding" and goes to lane 6 with "asset rush" and "sycophancy" as candidates.
- **Q34 walkthrough grading: separated from the critique.** C7/C8 CONFIRMED; C9's "/plan views
  the plan" demo is stale (it enters plan mode; no view command exists). A stale demo does not
  dent a design argument; graded separately per the claim ladder.
- **Q35 work items: NONE.** Nothing decided requires a plugin change.

## Outputs

- Rows: `docs/upstream/aihero-course.md` "Lane 4" section (9 rows + house-decisions paragraph).
- Work items: none.
- Lane-6 parcels: term candidates (design concept -> shared understanding, asset rush,
  sycophancy); the strongest coverage-index thesis line: "the fix for plan mode is not a better
  plan; it is a contract stage upstream of the plan, plus a plan stage that refuses to lock
  decisions inline."

## Notes for lane 5

- Expected mostly confirmation (frontier rounds, facts-vs-decisions, empty-frontier stop are
  attributed adoptions already recorded in the SSOT); check course-only additions: the
  grill-execute-CLEAR loop framing (the clear leg maps to our workflow spec-first mode and the
  handoff chain), and the lesson's decision-checklist examples.
- His grilling/grill-me SKILL.md texts may be wanted for exact-wording comparison; the
  `/workspace/mattpocock/skills` clone may be gone (probe: `git -C /workspace/mattpocock/skills
  rev-parse HEAD`, expect `068b6e0`; shallow re-clone command in the lane-4 handoff if needed).
