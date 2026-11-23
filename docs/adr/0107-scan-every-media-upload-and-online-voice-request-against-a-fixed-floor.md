# Scan every media upload and online voice request against a fixed floor

- Status: accepted
- Date: 2026-11-13
- Refs: owner decisions of 2026-11-13 (Q26, Q36, Q53, Q73; design thread T5)

## Context

Reviewer media carries text from the change into a public upload and into online voice services:
narration, frame text, screenshot sidecars and the pull request section. An attachment on a public
repository is permanent. `lib/redact.py` already loads gitleaks rules and redacts home paths, failing
closed when a rule cannot load.

## Decision

1. **`lib/media-render/media_scan.py` wraps `lib/redact.py`** and adds this machine's hostname and
   user name. It scans narration, frame text (from the storyboard's data, not OCR), screenshot
   sidecars and the rendered pull request section.
2. **It runs before every upload and before any text reaches an online voice.** A hit, or a
   fail-closed redactor, stops the run; nothing is uploaded or sent.
3. **The floor is fixed.** Configuration (`scan.strictness`) can only add to it.

## Considered options

- **A new scanner inside media-render.** Rejected: duplicates `redact.py`'s rule loading.
- **OCR over rendered frames.** Not adopted: frame text comes from storyboard data the scan already
  reads; screenshots without a text sidecar are refused instead.

## Consequences

- source-control and speech vendor `media_scan.py`, `lib/redact.py` and its rules.

## Revisit triggers

- A frame source whose text cannot be read without OCR becomes necessary.

## Amendment (2026-11-21): OCR scans evidence attachments

The revisit trigger fired for `/source-control:pull-request evidence`. Its screenshots and
recordings come from `/app-control:drive` or `/testing:run-e2e` runs, and before this amendment no
step scanned their pixels. Owner decision Q119 (2026-11-20, issue #16908) settles it:

1. **The evidence step reads each attached capture with OCR.**
   `skills/pull-request/scripts/evidence-ocr.py` reads each image, and each video frame ffmpeg's
   `mpdecimate` keeps, locally with tesseract; no image goes to an online service. Each image is
   upscaled and read twice, as captured and inverted, because tesseract 4.x reads dark text on a
   light background best and works best at 300 dpi or more
   ([ImproveQuality](https://github.com/tesseract-ocr/tessdoc/blob/main/ImproveQuality.md)). The text goes
   through the evidence step's own leak scan, the one its comment body gets.
2. **It fails closed.** A hit, a capture OCR reads no text from, or a host without tesseract or
   ffmpeg posts nothing.
3. **Frames are sampled with `mpdecimate`, not a fixed interval plus scene detection.**
   The decision's reading of the FFmpeg source on #16908: `mpdecimate` keeps a frame when one 8x8
   block changes past `hi`, so a token that changes a few blocks keeps its frame, while scene
   detection scores a whole-frame mean that a few changed blocks barely move. Its `hi` threshold defaults to 256, below ffmpeg's default of
   64*12 ([ffmpeg-filters, mpdecimate](https://ffmpeg.org/ffmpeg-filters.html#mpdecimate)), because
   the owner's synthetic probe found the default dropping dim text in a lossy recording. No value
   has been measured on real recordings, so `evidence_ocr_mpdecimate_hi` in
   `docs/conventions/source-control.yaml` sets it.
4. **Reviewer media is unchanged.** `media` still refuses a screenshot that names no frame-text
   sidecar. OCR misses text on screens often enough that replacing that refusal with OCR would
   weaken it.
5. **Synthetic data stays the main control.** Evidence captures of a regulated product show
   synthetic data only; the OCR scan is a backstop behind that rule.
6. **Measured cost.** As of 2026-11-22, on tesseract 5.5.0, ffmpeg 8.0.1 and a 24-core host, a set
   of three browser screenshots (1280x900, 768x1592, 390x900) and one 5 s 1920x1200 recording
   (125 frames, of which `mpdecimate` at `hi` 256 kept 3) scanned clean in 9.1 to 10.2 s over
   three runs: 4 captures, 6 images, 12 OCR passes, about 2.5 cores busy and a peak of about
   200 MB resident. One screenshot alone took 2.6 s and the recording alone 2.3 s, so the cost
   grows with the images read: each capture's stills plus the frames `mpdecimate` keeps. This
   measures run time only; it says nothing about which `hi` reads dim text in real recordings.
   Recheck when `evidence-ocr.py` changes the passes it makes per image, or tesseract changes
   major version.
