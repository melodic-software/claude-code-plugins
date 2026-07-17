# YouTube watch — vision + frame-selection pipeline

Detailed procedure behind two hub steps: the three-pass vision absorption (Skill protocol phase) and the deterministic frame-selection stages (reference). Criteria SSOT: `quality-gates.md`.

## Vision absorption (three-pass)

Checklist: `watching/frame-triage-checklist.json`; **JSON SSOT** + rendered markdown.

- **Pass 1 — contact-sheet triage:** One subagent per sheet from `tempSession.contactSheetsDir` (or `key-frames/contact-sheets/`). Write `key-frames/triage/batches/sheet_NNN.json` (cells per `sheet-frame-index.json`). Merge: `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/merge-triage-json.js "<slice>"`; validate: `validate-triage-json.js`; render: `render-triage-log.js`.
- **Pass 2 — detail reads:** All `keep-detail` frames + transcript interleave (`key-frames/selection.json` timeline). Escalate text-dense frames to **1920×1080**.
- **Pass 3 — transcript alignment:** For each densification window in `coverage-plan.json`, confirm ≥1 promoted or logged frame; gaps → `key-frames/visual-gaps.md`.
- **On-screen URLs:** Merge into `source/harvested-links.json` via `mergeHarvestedLinks()`.
- **Promote:** Write `key-frames/promotion-decisions.json` (vision verdict per candidate PNG). Apply: `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/vision-gated-promote.js "<slice>"`. Sparse synthesis OK; no quota filler.
- **Pre-promotion gate:** Read the actual PNG; reject deck-covered slides, talking-head, transcript-redundant, unreadable, mislabeled. See `synthesisPromotionBar` + `synthesis-contract.md`.
- **Post-promotion review:** One subagent reads every `frames/*.png`; write `key-frames/key-frame-quality-audit.json` (substantive `note` per frame, min 20 chars); render `render-quality-audit.js` + `render-key-frames-manifest.js`. **Delete** failures with `pass: false`.
- **Repair pass (when filename verify fails):** `node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watch/repair-synthesis-promotions.js "<slice-dir>"` — semantic renames from `gapNote`, reject generic pipeline placeholders, fix forbidden sessions.

## Frame selection pipeline (reference)

Deterministic stages in `watching/orchestrate-watching.js`:

1. ffprobe duration + `compute-coverage-plan.js` dynamic targets (no hard cap)
2. Scene-detect + phash dedup + stratified interval + cue-anchor extractions (`extract-anchor-frames.js`)
3. Transcript densification windows (`watching/densification.js`)
4. Contact-sheet batching for triage (`watching/timestamp-interleave.js`)

Standalone pipeline (when video + VTT already acquired):

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" watching/run-watching-pipeline.js "<video-path>" "<vtt-path>"
```

Metadata-only link harvest:

```bash
node "${CLAUDE_PLUGIN_ROOT}/skills/youtube-digest/extraction/run.mjs" harvesting/run-harvest.js "<info-json-path>"
```
