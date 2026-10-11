# Vision JSON shapes: agent-authored files

Phase 4 of the watch (`context/watch-pipeline.md`) has subagents write three JSON files by hand.
The validators reject anything off-shape, so copy the block for the file you are writing, keep
every key, and replace the values. Each brief that asks a subagent for one of these files carries
that file's section of this template.

Tooling writes `sheet-frame-index.json`, `triage/manifest.json` and `promotion-map.json`. Never
author those by hand.

## Per-sheet triage: `key-frames/triage/batches/sheet_NNN.json`

One file per contact sheet, written by that sheet's subagent. The brief also carries the sheet's
entry from `key-frames/sheet-frame-index.json`, because the cells must match it.
`merge-triage-json.js` validates each file and builds `triage/manifest.json`, which
`validate-triage-json.js` checks against the index.

| Key | Rule |
| --- | --- |
| `sheetId` | `sheet_` plus three digits, the same id the index gives the sheet. |
| `reviewedAt` | ISO 8601 timestamp of the review, for example `2026-10-10T19:54:41Z`. |
| `model` | The model id of the subagent that read the sheet. Required. `selection-signals`, `heuristic` and `prng` are refused, because triage must come from a model reading the image. |
| `cells` | Exactly as many entries as the index lists for this sheet: 16 for a full sheet, fewer for a short last sheet. |
| `cells[].cell` | Cell id `R<row>C<col>`, rows and columns 1 to 4, row-major (`R1C1` to `R1C4`, then `R2C1`). Each id once. A sheet of N cells uses the first N ids. |
| `cells[].frame` | The frame file name, copied exactly from the index entry for that cell. |
| `cells[].verdict` | One of `keep-detail`, `promote-key-frame`, `duplicate`, `blur`, `talking-head-only`, `skip`. |
| `cells[].note` | Optional. Shown in the rendered `frame-triage-log.md`. |

Worked example, for a short last sheet whose index entry lists four cells:

```json
{
  "sheetId": "sheet_007",
  "reviewedAt": "2026-10-10T19:54:41Z",
  "model": "claude-opus-5-5",
  "cells": [
    { "cell": "R1C1", "frame": "scene_0421.png", "verdict": "promote-key-frame", "note": "Architecture diagram: queue, worker pool, retry topic" },
    { "cell": "R1C2", "frame": "scene_0422.png", "verdict": "duplicate", "note": "Same diagram as R1C1" },
    { "cell": "R1C3", "frame": "interval_0130.png", "verdict": "talking-head-only" },
    { "cell": "R1C4", "frame": "interval_0131.png", "verdict": "keep-detail", "note": "Terminal output too small to read at sheet scale" }
  ]
}
```

## Promotion decisions: `key-frames/promotion-decisions.json`

One file per slice: the vision verdict for every candidate PNG, written after reading the actual
image (`context/synthesis-contract.md` sets the bar). `vision-gated-promote.js` and
`validate-promotion-decisions.js` read it.

| Key | Rule |
| --- | --- |
| `decisions` | Array, one row per candidate. |
| `sourceFile` | Required. The frame file name in the temp session's frames directory; promotion fails when the file is not there. |
| `verdict` | `promote` or `reject`. |
| `destName` | Required for `promote`. Semantic kebab-case name, `.png` optional: lowercase letters, digits and single hyphens. Pipeline tokens are refused: the prefixes `at-`, `scene_`, `anchor_`, `dens-`, `densification-`, `code-code-`, `code-demo-`, `code-terminal-`, `code-slides-`, `win-code-`, and the forms `dens-scene<N>`, `-m<N>.png` and `-m<N>-s<N>.png`. |
| `gapNote` | Required for `promote`, at least 8 characters after trimming: what the frame shows that the transcript does not. |
| `session` | Optional. The claim-inventory segment the frame belongs to. A slug ending in `-topup` or starting with `pipeline-` is refused. |
| `rejectReason` | Required for `reject`, a string. |

Worked example:

```json
{
  "decisions": [
    {
      "sourceFile": "scene_0421.png",
      "verdict": "promote",
      "destName": "retry-topic-architecture",
      "gapNote": "Diagram shows the retry topic between the queue and the worker pool; the talk only names it.",
      "session": "keynote-reliability"
    },
    {
      "sourceFile": "interval_0130.png",
      "verdict": "reject",
      "rejectReason": "talking-head"
    }
  ]
}
```

## Post-promotion audit: `key-frames/key-frame-quality-audit.json`

One file per slice, written by the subagent that reads every `key-frames/frames/*.png` after
promotion. `render-quality-audit.js` renders it to `key-frame-quality-audit.md`, and
`check-watch-outcomes.js` validates it.

| Key | Rule |
| --- | --- |
| `reviewedAt` | ISO 8601 timestamp of the review. |
| `files` | One row per PNG in `key-frames/frames/`; the row count must equal the PNG count. |
| `files[].name` | The PNG file name, ending `.png`. |
| `files[].pass` | Boolean. A `false` row fails the outcome check: delete or fix that frame, then audit again. |
| `files[].note` | Required when `pass` is `true`: at least 20 characters after trimming, saying what was checked. A stub such as `ok` or `looks good` fails. |

Worked example:

```json
{
  "reviewedAt": "2026-10-10T20:12:03Z",
  "files": [
    {
      "name": "retry-topic-architecture.png",
      "pass": true,
      "note": "Readable diagram; labels match the gap note and the 14:05 transcript passage."
    }
  ]
}
```
