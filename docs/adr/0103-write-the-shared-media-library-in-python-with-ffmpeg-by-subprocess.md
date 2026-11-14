# Write the shared media library in Python with ffmpeg by subprocess

- Status: accepted
- Date: 2026-11-13
- Refs: owner decisions of 2026-11-13 (Q43, Q43a, Q86, Q87; design thread T1)

## Context

Four plugins encode video today, each with its own ffmpeg arguments: explainer-video, animation,
pixel-art and playwright's demo-video. Their encode, captions, loudness and quality-control code is
Python; animation and demo-video capture Chromium through Node and playwright-core, and pixel-art drives
Chromium over raw CDP from Python. The produced-video feature adds a still-frame renderer and needs one
implementation per media concern.

## Decision

1. **`lib/media-render/` is Python ≥ 3.12** (tested on 3.12 to 3.14), standard library plus
   Playwright for Python, with ffmpeg and ffprobe run by subprocess. One file per concern: capture,
   frame templates, timeline, captions, encode, loudness, verify, size, contact sheet, scan.
2. **Vendored per file** under [ADR 0019](0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md),
   each copy listed in `scripts/shared-copies.txt`. Library files import no plugin and name no voice
   provider.
3. **Only the new still-frame renderer uses `media_capture.py`.** animation's `capture.mjs` (which
   backs its released `playwright_core` option) and pixel-art's canvas capture stay; both move only
   their encode onto the library. demo-video's live-app replay stays Node; its encode, captions and
   loudness move.
4. **Per-skill encode settings become named profiles** in `media_encode.py` that keep today's
   arguments, so moved plugins' output does not change.
5. **The quality check is luma (Y) SSIM ≥ 0.999 per sampled frame**, not whole-frame SSIM: 4:2:0
   chroma on colored code text holds whole-frame SSIM below 0.99 at any CRF (probe, 2026-11-13).

### One-way doors

The language of a vendored library: every carrier plugin takes Python and its version floor.

## Considered options

- **Python core plus one Node capture module.** Rejected: pixel-art would gain Node, and two capture
  stacks would stay.
- **All Node.** Rejected: rewrites about 2,000 lines of working Python encode and quality-control
  code across four plugins, and speech stays Python, so two languages remain anyway.
- **PyAV for in-process encoding.** Rejected: its own README calls it "more of a hindrance than a
  help" when the ffmpeg command line does the job.
- **Move animation and pixel-art capture onto Playwright for Python.** Rejected: animation exposes a
  released `playwright_core` option used across 36 files; pixel-art is stdlib-only canvas capture.

## Consequences

- explainer-video gains `playwright==1.65.1`; its Chromium installs on the first stills render, and in CI.
- Each plugin migration is its own pull request, with a golden capture taken before the move.

## Revisit triggers

- A later major release retires animation's `playwright_core` option.
- An operation the ffmpeg command line cannot express.
- kokoro-onnx supports Python 3.14 (lifts the voice adapter's cap).
