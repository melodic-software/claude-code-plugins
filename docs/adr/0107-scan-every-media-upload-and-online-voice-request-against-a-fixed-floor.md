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
