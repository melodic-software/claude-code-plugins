# YouTube watch — quality gates

Binary criteria for `/youtube watch`. A phase is not done when it *feels* done — it is done when artifact-grounded checks pass. Same discipline as `/research` "Outcome gate" and `/workflow` checklist ticks.

**SSOT for numeric floors:** `outcomeFloors()` in `.claude/skills/youtube/extraction/evals/check-watch-outcomes.js` (do not duplicate numbers elsewhere without syncing).

## Tick discipline

1. Initialize `watch-checklist.md` at skill session start (`init-watch-checklist.js`).
2. Tick `[ ]` → `[x]` only after **verification evidence** — cite command exit code, artifact path, or verify row in the checklist or adjacent log line.
3. **Blocking verify scripts** must exit 0 before ticking the matching phase-complete box or setting `watch.json` `status: complete`.
4. Satisficing ("we have 14 frames, close enough") is a FAIL — re-run the named phase.
5. **Synthesis contract:** `context/synthesis-contract.md` — transcript-gap bar, vision-gated names, staged deck-first; overrides count-chasing.

## Content class → outcome floors

Detected from `key-frames/vision-plan.md` (backtick class tag). Floors apply to synthesis promotions in `key-frames/frames/` only.

| Class | Duration signal | Min synthesis frames | Min / hour | Min / session | Min sheet triage | Densification (frame or gap) | Densification (frame only) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `conference-multi-session` | any, or ≥4h | `max(sessions × 4, ceil(hours × 5))` | 5.0 | 3 | 75% | 35% | 25% |
| (default long) | ≥4h without class | same as conference | 5.0 | 3 | 75% | 35% | 25% |
| (default medium) | ≥1h, &lt;4h | `max(8, ceil(hours × 3))` | 3.0 | 2 | 50% | 20% | 15% |
| (default short) | &lt;1h | 2 | 1.0 | 1 | 25% | 10% | 5% |

**Densification coverage:** each window in `key-frames/selection.json` `densificationWindows` must have ≥1 promoted frame timestamp inside the window **or** a gap row in `key-frames/visual-gaps.md` for that region.

**Session coverage:** each session in `research/claim-inventory.md` must have ≥1 promoted synthesis frame whose timestamp falls inside the session boundary (or gap logged — prefer frame).

## Phase gates (ordered)

This table lists the **blocking artifacts per phase** (which must exist before the phase is done). The artifact's **lane, staged verdict, KIND, and producer** are owned by the `/youtube` skill's "Output contract" table — that is the single authoritative enumeration; do not restate staging here.

| Phase | Blocking artifacts | Verify script |
| --- | --- | --- |
| 0 Prerequisites | deps installed | Pre-computed context in SKILL.md — no MISSING |
| 0b Companion (when `source/companion-sources.md` exists) | `source/companion-digest/README.md`, `source/companion-digest/<section-slug>.md` per brief | Every section row digested; `mark-phase companion` before Phase 1; SSOT: `companion-primary-sources.md` |
| 1 CLI bootstrap | `source/transcript.txt`, `run-state/watch.json`, `key-frames/selection.json`, tempSession paths exist | `run-watch.js` exit 0; spot-read transcript; `highVolume` true when sheets ≥8 or duration ≥2h |
| 2 Vision plan | `key-frames/vision-plan.md` | Content class + segments + triage scope; inspection sample of 3–5 sheets recorded |
| 3 Claim landscape | `research/claim-inventory.md`, draft `research/research-agenda.md` | ≥4 claims/session for conferences; ≥40 total claims for ≥4h VOD |
| 4 Vision pass 1 | `key-frames/frame-triage-log.md` | One `## sheet_NNN` per contact sheet with per-cell verdicts |
| 5 Vision pass 2 | `key-frames/visual-frames.md` | Every `keep-detail` frame read at native res; text-dense escalated to 1920×1080 |
| 3b Deck harvest A | `source/deck-inventory.md`, `source/decks/` | Metadata deck URLs fetched before full vision fan-out when candidates exist |
| 6 Vision pass 3 + promote | `key-frames/frames/*.png`, manifest + audit | Vision-gated semantic filename + gap note before copy; deck pass B after on-screen URLs |
| 7 Research | `RESEARCH.md`, `research/findings/` | `check-research-complete.js` exit 0 |
| 8 Synthesis | `recommendations/*` hub + menu + takeaways + questions + interview, README | Templates per skill `templates/recommendations/` |
| 9 Outcome | `verification/<ISO-basic>Z-watch-outcomes.md` | `check-watch-outcomes.js --write-report` exit 0 |

`mark-phase` (`watch-state.js mark-phase <slice-dir> <phase>`) in `watch.json` is allowed **only** after the row's artifacts and verify scripts for that wave succeed.

## Outcome verification (host verify script)

`node .claude/skills/youtube/extraction/evals/check-watch-outcomes.js "<slice-dir>" --write-report`

| ID | Binary criterion | FAIL → |
| --- | --- | --- |
| `vision-plan` | `key-frames/vision-plan.md` exists (&gt;100 chars) | Phase 2 — write plan before fan-out |
| `claim-inventory` | `research/claim-inventory.md` exists | Phase 3 — landscape before research |
| `synthesis-count-floor` | synthesis PNG count ≥ class floor | **warn** — do not promote junk; see `synthesis-contract.md` |
| `synthesis-per-hour` | count / hours ≥ floor | **warn** |
| `sheet-triage-coverage` | triage log sheets / contact sheets ≥ ratio | Phase 4 — fan out per-sheet triage |
| `triage-json-present` | `key-frames/triage/manifest.json` validates | Phase 4 — merge batch JSON; no markdown-only triage |
| `triage-cell-completeness` | cells per sheet match `sheet-frame-index.json` | Phase 4 — re-run sheet fan-out |
| `triage-agentic-required` | every sheet has agentic `model` (not `selection-signals` / `heuristic` / `prng`) | Phase 4 — vision subagent per sheet |
| `triage-batch-files-present` | `key-frames/triage/batches/sheet_NNN.json` exists for every manifest sheet | Phase 4 — write batch JSON before merge |
| `heuristic-triage-forbidden` | markdown triage requires JSON manifest | Phase 4 — do not PRNG/heuristic-fill triage log |
| `densification-alignment` | windows with frame or gap ≥ ratio | Phase 6 — pass 3 alignment |
| `session-visual-coverage` | every claim-inventory session has in-window promotion | Phase 6 — per-session frame |
| `promotion-decisions-present` | `key-frames/promotion-decisions.json` when synthesis PNGs exist | Phase 6 — vision pass before copy |
| `synthesis-filename-policy` | no pipeline tokens (`dens-*`, `code-code-*`, `-mNNN`, etc.) | Phase 6 — rename from on-screen content; content-class rejects stay agent vision |
| `actionable-artifacts` | `recommendations/` hub + four docs | Phase 8 — copy `templates/recommendations/` |
| `watch-checklist-complete` | blocking ticks when `status: complete` | Phase 9 — tick 8.x + 9.1–9.4 with evidence |
| `promotion-traceability` | every synthesis PNG has promote decision + `promotion-map.json` | Phase 6 — run `vision-gated-promote.js` |
| `manifest-audit-parity` | manifest + audit JSON rows match PNG count | Phase 6 — render from JSON SSOT |
| `quality-audit-failures` | no `pass: false` in `key-frame-quality-audit.json` | Phase 6 — delete failures |
| `quality-audit` | manifest + audit `.md` + `key-frame-quality-audit.json` | Phase 6 — post-promotion review |
| `vision-metrics-honesty` (warn) | `watch.json` vision metrics ≈ triage log | Fix metrics drift; do not claim 48 triaged when log shows 6 |

### Structural vs vision fidelity

Host verify scripts prove **traceability and shape** (JSON valid, batch files on disk, semantic filename policy, promotion-map parity). They do **not** prove subagents opened contact sheets or that filenames match on-screen content.

**Vision fidelity spot-check (required before claiming A+):** In a separate pass (fresh context OK), spot-check ≥10 synthesis PNGs (name ↔ content) and ≥3 contact sheets (verdicts ↔ JPG). Record notes in `watch-checklist.md` or slice README. Verify script exit 0 without spot-check = structural complete only.

## Research gate (host verify script)

`node .claude/skills/youtube/extraction/evals/check-research-complete.js "<slice-dir>"`

| Criterion | FAIL → |
| --- | --- |
| `RESEARCH.md` exists, ≥200 chars | Run research fan-out |
| `claim-inventory.md` exists | Phase 3 |
| No `pending` rows in `research-agenda.md` | Complete or defer each cluster |
| `research-review/*.md` count ≥ `done` agenda rows | Write per-cluster findings |
| At least one `done` or `deferred` row | Draft agenda from inventory |

Apply `/research` skill "Outcome gate" per cluster before marking agenda row `done`.

## Synthesis promotion bar

SSOT: `context/synthesis-contract.md`. JSON checklist: `watching/frame-triage-checklist.json` `synthesisPromotionBar`.

**Reject (delete or skip — do not promote):**

- talking-head-only, empty-or-transition, title-slide-only-without-data
- unreadable-text, mislabeled-capture, duplicate-of-promoted-frame
- static slide covered by fetched deck (`deck-inventory.md`)
- transcript/research already carries the claim
- automated filenames (`at-*`, `scene_*`, collision suffixes)

**Prefer:**

- code-or-diagram, metrics-or-diagram-readable, demo-ui-with-claim, on-screen URL not in harvest

**Pre-promotion:** Vision pass assigns semantic filename + gap note; read the actual PNG — cell index can mislabel.

**Post-promotion:** Review every `frames/*.png`. **Delete** failures — do not relocate junk under `key-frames/frames/`.

## Vision triage verdicts

Per cell in contact sheet (`frame-triage-checklist.json` `verdicts`):

`keep-detail` | `promote-key-frame` | `duplicate` | `blur` | `talking-head-only` | `skip`

**JSON SSOT:** subagents write `key-frames/triage/batches/sheet_NNN.json`; merge to `key-frames/triage/manifest.json`; render `key-frames/frame-triage-log.md` via `render-triage-log.js`. Do not treat markdown-only triage as complete.

**Promotion SSOT:** `key-frames/promotion-decisions.json` → `vision-gated-promote.js` → `promotion-map.json` (`promotion-name-map.js` loader). **Triage SSOT:** `key-frames/triage/batches/sheet_NNN.json` → `merge-triage-json.js` → `render-triage-log.js`. No signal-derived or bulk-promote shortcuts — verify scripts enforce agentic triage and vision-gated promotion.

## High-volume fan-out

When `watch.json` / `selection.json` sets `highVolume: true`:

- Pass 1: **one subagent per contact sheet** (no band-sampling shortcut)
- Do not truncate frames in temp session
- Sheet triage ratio floor is 75% for long conferences — partial triage fails the verify script

## Synthesis artifacts (phase 8)

| Artifact | Required |
| --- | --- |
| `recommendations/README.md` | Yes — hub linking menu, takeaways, questions, interview |
| `recommendations/menu.md` | Yes — P0–P2 repo applicability menu |
| `recommendations/takeaways.md` | Yes |
| `recommendations/questions.md` | Yes |
| `recommendations/interview.md` | Yes |
| `README.md` updated | Yes — per `templates/readme-journey.md` |
| Auto-implement | **No** — `/interview` → `/architect` → `/implement` |

## Complete slice

`watch.json` `status: complete` **only** when:

1. All phase-complete boxes ticked in `watch-checklist.md` (or honest deferral noted)
2. `check-research-complete.js` exit 0
3. `check-watch-outcomes.js --write-report` exit 0
4. `verification/<ISO-basic>Z-watch-outcomes.md` shows PASS
