# Watch checklist — {{VIDEO_SLUG}}

Initialized: {{INIT_TIMESTAMP}}

{{FLOORS_LINE}}

**Signals:** {{CONTACT_SHEET_COUNT}} contact sheets · {{DENSIFICATION_WINDOW_COUNT}} densification windows · highVolume={{HIGH_VOLUME}}

Tick only after verification evidence. Criteria SSOT: `quality-gates.md` (the `/knowledge:youtube` skill's quality-gate criteria).

---

## Phase 0 — Prerequisites

- [ ] **0.1** youtube-extraction deps installed — Verify: `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube/extraction/setup-deps.mjs"` exit 0
- [ ] **0.2** yt-dlp available — Verify: SKILL pre-computed context ≠ MISSING
- [ ] **0.3** ffmpeg available (watch only) — Verify: SKILL pre-computed context ≠ MISSING
- [ ] **0.4** ImageMagick 7 available (watch only) — Verify: SKILL pre-computed context ≠ MISSING

## Phase 0b — Companion primary sources (when `source/companion-sources.md` exists)

- [ ] **0b.1** Brief read — Verify: `source/companion-sources.md` present; section fan-out table complete
- [ ] **0b.2** Companion URL(s) deep-fetched — Verify: WebFetch full page per URL; not surface skim
- [ ] **0b.3** Section fan-out complete — Verify: `source/companion-digest/<section-slug>.md` for every row in brief
- [ ] **0b.4** Hub digest written — Verify: `source/companion-digest/README.md` links all section shards
- [ ] **0b.5** `mark-phase <slice-dir> companion` only after 0b.1–0b.4 — Verify: `watch.json`; run **before** Phase 1 on fresh watch

## Phase 1 — CLI bootstrap

- [ ] **1.1** `run-watch.js` (or resume) succeeded — Verify: exit 0; `watch.json` present
- [ ] **1.2** `transcript.txt` readable — Verify: spot-read; not empty/error stub
- [ ] **1.3** `key-frames/selection.json` matches `watch.json` metrics — Verify: frame count, `contactSheets`, `densificationWindows`
- [ ] **1.4** tempSession paths exist on disk — Verify: `contactSheetsDir`, frames dir from `watch.json` `artifactPaths`
- [ ] **1.5** `highVolume` correct for long VOD — Verify: true when sheets ≥8 or duration ≥2h or densification ≥30
- [ ] **1.6** CLI phases marked complete only after 1.1–1.5 — Verify: acquire, transcript, watching, harvest in `watch.json`

## Phase 2 — Vision plan (before fan-out)

- [ ] **2.1** `key-frames/vision-plan.md` written — Verify: content class `` `{{CONTENT_CLASS}}` `` (or updated class), session segments, triage scope
- [ ] **2.2** Inspection sample (3–5 sheets across segments) — Verify: sample notes in vision-plan (cells seen, escalation triggers)
- [ ] **2.3** Promotion targets + dedupe rules stated — Verify: vision-plan section references synthesis bar

## Phase 3 — Claim landscape (before research)

- [ ] **3.1** `research/claim-inventory.md` — Verify: sessions with boundaries; ≥4 claims/session (conference); ≥40 claims if ≥4h
- [ ] **3.2** `research/research-agenda.md` drafted from inventory — Verify: cluster rows map to claim IDs
- [ ] **3.3** No research fan-out started before 3.1 — Verify: agenda exists before first research cluster

## Phase 3b — Deck harvest pass A (before full vision fan-out)

- [ ] **3b.1** `harvested-links.json` typed (`deck` \| `repo` \| `doc` \| `other`) — Verify: metadata/chapter URLs classified
- [ ] **3b.2** Deck candidates fetched — Verify: `source/deck-inventory.md` + `source/decks/<session-slug>/` or failed row logged
- [ ] **3b.3** `research/sources.md` started — Verify: template `templates/sources.md`; decks/repos cited

## Phase 4 — Vision pass 1 (contact-sheet triage)

- [ ] **4.0** `tempSession.contactSheetsDir` verified — Verify: list `sheet_*.jpg` count = {{CONTACT_SHEET_COUNT}}
- [ ] **4.1** High-volume fan-out used when `highVolume=true` — Verify: one subagent per sheet (no band-sample shortcut)

### Per-sheet triage (every sheet — blocking)

{{SHEET_CHECKBOXES}}

- [ ] **4.8** Triage JSON merged — Verify: `key-frames/triage/manifest.json` + `key-frames/triage/batches/sheet_NNN.json` per sheet; `validate-triage-json.js` exit 0
- [ ] **4.9** Triage log complete — Verify: `countTriageSheetsLogged` / {{CONTACT_SHEET_COUNT}} ≥ {{FLOOR_SHEET_TRIAGE_PCT}}% before phase 6 complete
- [ ] **4b.1** On-screen URLs merged — Verify: `harvested-links.json` updated
- [ ] **4b.2** Deck harvest pass B — Verify: new deck URLs fetched; remaining sheets re-filtered with deck inventory

## Phase 5 — Vision pass 2 (detail reads)

- [ ] **5.1** Every `keep-detail` frame read at native resolution — Verify: rows in `key-frames/visual-frames.md`
- [ ] **5.2** Text-dense frames escalated to 1920×1080 — Verify: escalation noted in visual-frames or triage log
- [ ] **5.3** Transcript interleave for ambiguous cells — Verify: `key-frames/selection.json` timeline used where needed

## Phase 6 — Vision pass 3, promotion, quality audit

- [ ] **6.1** Each densification window: promotion OR `key-frames/visual-gaps.md` row — Verify: {{DENSIFICATION_WINDOW_COUNT}} windows addressed
- [ ] **6.2** Each session segment: ≥1 synthesis frame in-window OR gap — Verify: against `claim-inventory.md` boundaries
- [ ] **6.3** Pre-promotion: read each candidate PNG — Verify: no promote from filename/cell index alone
- [ ] **6.4** Vision-gated promote → `key-frames/frames/` — Verify: semantic filenames only (`synthesis-contract.md`); count floor warn-only
- [ ] **6.5** On-screen URLs merged — Verify: `source/harvested-links.json` updated if URLs found
- [ ] **6.6** Post-promotion review of every `frames/*.png` — Verify: failures **deleted**, not kept under `key-frames/frames/`
- [ ] **6.7** `key-frames/key-frames-manifest.md` + `key-frames/key-frame-quality-audit.md` — Verify: files exist; audit covers each synthesis file
- [ ] **6.8** `mark-phase <slice-dir> vision` only after 4.x–6.7 — Verify: `watch.json` vision metrics honest vs triage log

## Phase 7 — Research

- [ ] **7.1** Each agenda cluster `done` or `deferred` with reason — Verify: no `pending` in `research-agenda.md`
- [ ] **7.2** Per done cluster: finding file or inline in `RESEARCH.md` — Verify: research outcome gate per cluster
- [ ] **7.3** `RESEARCH.md` slice summary — Verify: ≥200 chars; conflicts + gaps sections
- [ ] **7.4** Top harvested URLs fetched; repos analyzed to temp if GitHub links — Verify: fetch log / `analyze-harvested-repos.js` when applicable
- [ ] **7.5** Research verify — Verify: `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube/extraction/run.mjs" evals/check-research-complete.js "<slice-dir>"` exit 0
- [ ] **7.6** `mark-phase <slice-dir> research` only after 7.5 — Verify: `watch.json`

## Phase 8 — Synthesis

- [ ] **8.1** `recommendations/menu.md` — Verify: categories + P0–P2
- [ ] **8.2** `recommendations/takeaways.md`
- [ ] **8.3** `recommendations/questions.md`
- [ ] **8.4** `recommendations/interview.md` with POC/full-slice menu
- [ ] **8.0** `recommendations/README.md` hub links menu, takeaways, questions, interview
- [ ] **8.5** `README.md` per `templates/readme-journey.md`
- [ ] **8.6** No auto-implement — Verify: no code changes without `/interview`
- [ ] **8.7** `mark-phase <slice-dir> synthesis` only after 8.1–8.5

## Phase 9 — Outcome verification (mandatory before complete)

- [ ] **9.1** Host verify — Verify: `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube/extraction/run.mjs" evals/check-watch-outcomes.js "<slice-dir>" --write-report` exit 0
- [ ] **9.2** `verification/<ISO-basic>Z-watch-outcomes.md` shows PASS — Verify: all `fail` severity checks green
- [ ] **9.3** `watch.json` `status: complete` only after 9.1 — Verify: not complete while synthesizing
- [ ] **9.4** Vision fidelity spot-check (A+ gate) — Verify: ≥10 synthesis PNG images name↔content + ≥3 contact sheets verdict↔JPG; notes in Resume notes below. Verify script exit 0 alone is structural only.

---

## Resume notes

*Evidence citations (command outputs, paths, subagent IDs) for ticks:*

```
(paste verification evidence as you tick)
```
