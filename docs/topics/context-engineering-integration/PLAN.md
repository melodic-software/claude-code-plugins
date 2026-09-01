# Context-engineering corpus integration — decision contract

## Brief

Status: **pending final sign-off** — every answer below, including the provisionally locked
ones, awaits the operator's explicit sign-off sheet confirmation (standing directive,
2026-08-31: "I will confirm final answers for ALL questions already answered and all ones you
are answering. I want final sign off."). Nothing here executes before that.

Grounded as of commit `335081c6` (origin/main, fetched 2026-09-01). Evidence artifacts live in
the session's memory tier (`.work/context-engineering-integration/` and
`.work/context-eng-corpus/`): two byte-verified docpage-digest slices (P1 = the trq212
"New rules of context engineering for Claude 5 models" X article; P2 = the Anthropic
"Effective context engineering for AI agents" engineering post, published 2025-09-29), nine
deep tier-2 page inventories, a fresh unbiased paragraph-grain sweep with four-lens critical
apparatus, bidirectional reconciliation against the prior plan and field-guide audit, a master
coverage ledger, verified EXPLORE/RESEARCH artifacts, blindspot cards B1-B10, brainstorm
candidates C1-C12, and a fresh-context devils-advocate report (1 CRITICAL / 4 HIGH). The
memory tier is never committed; this Brief is the durable record and inlines every
decision-bearing fact.

### TLDR

Absorb the two-article context-engineering corpus (plus its nine linked pages) into this
marketplace's decision record, and integrate what earns its place: inputs to the in-flight
`context-engineering-claude-5` plan, a small set of doc+wiring artifacts, two skill-vocabulary
extensions, and recorded settled facts — under OPINION-tier/provenance discipline, with
everything gated on the operator's final sign-off.

### Goal

A signed-off answer set (Q1-Q14) that routes every corpus finding to a named, durable home —
or an explicit deferral — without duplicating the prior plan's territory, silently expanding
its locked Brief, or authoring against surfaces that have drifted.

### Constraints

- Final sign-off gate: the operator confirms ALL answers; "go with recommended" assembles the
  sheet, never skips the gate.
- The prior plan `docs/topics/context-engineering-claude-5/` owns the P1 instruction-audit
  lane; this effort never re-absorbs P1 or edits that plan's design docs unilaterally.
- Memory-tier evidence is cited by content (inlined here) or by tracker item, never by bare
  `.work` path in anything meant to outlive the session.
- Sequencing: the work-folder-hierarchy / topic-docs v3 clean-break wave (#3552, Brief locked
  2026-09-01) restructures the `.work` substrate; Q12/C1/B9-dependent work orders against it
  (operator sequencing question on the sheet).

### Provisionally locked answers (rounds 1-2; refined by blindspot/devils-advocate; ALL pending sign-off)

- **Q1 (deletion evidence threshold):** two-tier — editorial audit-instructions pass may
  delete trivial legacy guards; consequential rules need ledger evidence. Refinement (B5 +
  DA-MEDIUM): express the consequential tier in unhobble's existing two-rows-same-cause
  grammar, BUT that grammar currently defends re-adds after a full strip, not per-rule
  deletions — the deletion tier needs an attribution design (observation window, same-cause
  rule) before it becomes a skill edit.
- **Q2 (exception register):** yes — a docs/conventions owner doc naming the "highly
  important areas" where hard constraints stay. Refinements (B2 + DA-MEDIUM): inert unless
  wired — same change names it in consuming skills' criteria text; register is
  NON-EXHAUSTIVE with a tighten-only clause; cross-referenced from
  instruction-placement's routing-rubric (Gate 0) so one concern keeps one adjudication
  chain; omission never licenses deletion.
- **Q3 (conflict coverage):** superseded by evidence — audit-instructions I15 scopes
  conflicts to resident-surface pairs BY RECORDED DESIGN (its criteria file cites the
  article's user-request example as Source). The user-request-clash axis is a boundary
  REOPEN with a detectability answer, filed as an OPINION-tier detector candidate to the
  prior plan's catalog via tracker item (see Q8/C9), not a simple extension.
- **Q4 (/doctor):** verification DONE by research — commands.md (v2.1.205/206): /doctor
  trims/dedupes/migrates CLAUDE.md guidance into skills and finds unused skills by context
  cost; no official surface says "rightsize" or skill-content simplification. The
  audit-native-overlap run is unnecessary (Q9); repo docs citing /doctor cite commands.md.
- **Q5 (80% claim posture):** OPINION-tier WITH directional-corroboration annotation.
  Carriers (corrected 2026-09-01 by validator 2): the X article AND its claude.com/blog twin
  (the-new-rules-of-context-engineering-for-claude-5-generation-models) both carry the
  figure — under the repo's recorded precedent (audit-instructions criteria.md:153-158) a
  vendor blog corroborates rather than defines, so the tier stands; changelog v2.1.154
  ("lean system prompt is now the default") corroborates direction only. Magnitude and "no
  measurable loss" stay vendor-voice (verifier's world-truth ruling); scope qualifier ("on
  our coding evaluations") always carried. Never phrase the annotation as "no official
  surface carries it" — falsifiable in one fetch.
- **Q6 (model-upgrade re-test):** documented trigger only; the shipped `audit-pass` re-run
  contract (lease/epoch, suppression, three-scope inventory) is the ritual vehicle. Cite
  shipped reference files, not design/rerun-contract.md (drifted; flagged to plan owner).
- **Q7 (prior-plan relationship):** fresh unbiased pass FIRST (executed 2026-08-31:
  10 fresh sweeps, 4 reconciliation adjudications, coverage ledger); prior work is one
  reconciliation input. Residual decision → sign-off sheet: is the prior plan alive
  (resume / finish / absorb-and-close)? Routing without that answer is burial.

### Open questions for the sign-off sheet (recommended dispositions; operator decides)

- **Q8:** split the gap-cluster routing — only execution-changing inputs (I15 reopen,
  rerun-contract drift, CF-7 wording, P2-never-engaged) go to the prior plan via the C2
  note + phase-section references + tracker items; G-SEC (guardrail-deletion / memory-
  poisoning security) becomes its OWN work item now (security cost of burial); G-THESIS +
  G-PRECOND ride with the corpus critical apparatus (Q12); G-GOV is green-field with C10.
- **Q9:** drop the audit-native-overlap /doctor run (evidence inlined at Q4); CF-7 filed as
  a wording fix, tier logic unaffected (venue characterization was litigated in #2036/#2057
  — the note engages that history, headline softened from "authority-inflating").
- **Q10:** adopt the prior plan's OPINION-tier vocabulary corpus-wide + snapshot-dated
  citations. REVISED per devils-advocate: CF-1 does NOT fire upstream-drift's recorded
  content-hashing reopen trigger (no committed stale stamp caused a defect) — record CF-1 as
  adjacent near-miss evidence in a dated changelog entry per that convention's own v1.6.2
  precedent, and file the hash store as its own designed issue via tracker; do not edit the
  deferral text.
- **Q11:** cite-only now; graduation + custody policy deferred to V7, sequenced after the
  topic-docs v3 wave.
- **Q12:** critical-apparatus home rides the corpus slices pending V7 + v3 sequencing; the
  durable pointer is this Brief + tracker items.
- **Q13:** apply the P2-slice zero-cost merges as corrections round 4 (bakery
  transcriptions, compaction caveat C105, sub-agent economics) with re-pin + re-verify —
  noting the slice is memory-tier until Q11/V7 graduation decides otherwise.
- **Q14:** the dated input note lands under the prior plan's `design/` per topic-docs, is
  referenced from PLAN.md AND from the phase sections it gates (Phase 8 criteria edits,
  Phase 10 reconcile) in the same commit, with tracker items for each actionable payload.

### Validation record

Two independent fresh-context validators (rationale withheld, devils-advocate evidence
discipline, 2026-09-01) each audited all seven locked decisions: 14/14 CONFIRMED, 0
CHALLENGED, 0 RECLASSIFIED. Standing findings carried to execution: (1) D3's tracker item
must be written to survive an absorb-and-close outcome on Q15; (2) D1's consequential tier
is deliberately unclearable until its attribution design exists — the ordering is enforced,
not incidental; (3) Q5's annotation cites both first-party carriers (above); (4) D2's
same-change wiring into shipped skills respects the repo/product "two hats" boundary
unhobble records.

### Captured assumptions

- Same operator owns this effort, the prior plan, and the topic-docs v3 wave; sequencing is
  theirs alone (sheet question).
- Claude Code surfaces verified 2026-08-31/09-01 (v2.1.252 changelog recency gate); any
  execution re-verifies against then-current surfaces per the repo's upstream-drift
  discipline.
- The `#` memory hotkey is REMOVED (changelog v2.0.70) — settled fact, recorded; the memory
  tool and context editing are platform-side (memory tool: all Claude 4+ models, no beta
  header; context editing: beta) and Claude Code exposes neither natively (analogues:
  auto-memory, compaction).

### Out of scope

- Re-absorbing P1 into a second plan; editing the prior plan's design docs beyond the Q14
  note; implementing C6-C12 before sign-off; graduating corpus slices before V7/v3
  sequencing; referenced-external sources (Karpathy, context-rot study, arXiv, Willison)
  beyond cataloging.

### Acceptance criteria

- The sign-off sheet presents ALL of Q1-Q14 in their refined forms with the operator's
  explicit confirmation recorded per answer; no answer executes unconfirmed.
- Every accepted routing has a durable receipt (commit, tracker item, or phase-section
  reference) — nothing disposed by memory-tier note alone.
- Post-sign-off execution follows the per-unit loop: one artifact at a time — apply, verify
  (the repo's own gates), close.

### Deferred questions

- Q8 — split routing of gap clusters (arbiter: USER-RESERVED; recommended split above).
- Q9 — drop /doctor overlap run + CF-7 wording fix (arbiter: USER-RESERVED).
- Q10 — OPINION-tier + snapshot citations + CF-1 as near-miss evidence, hash store as its
  own issue (arbiter: USER-RESERVED).
- Q11 — cite-only now; graduation to V7 after v3 (arbiter: USER-RESERVED).
- Q12 — critical-apparatus home pending V7/v3 (arbiter: USER-RESERVED).
- Q13 — P2-slice corrections round 4 (arbiter: USER-RESERVED).
- Q14 — input-note placement + phase references + tracker receipts (arbiter: USER-RESERVED).
- Q15 — is `docs/topics/context-engineering-claude-5` alive: resume, finish, or
  absorb-and-close? (arbiter: USER-RESERVED; surfaced by the devils-advocate pass).
- Q16 — sequencing of this integration against the topic-docs v3 clean-break wave (#3552)
  (arbiter: USER-RESERVED).

## Plan

(Empty — `/planning:plan` fills this after sign-off.)
