# Changelog for the Rendered Views Convention

Notable changes to the rendered-views contract. The contract is not SemVer-
versioned; this log records posture rulings that do not change the boundary
rule, genre rubric, or cascade keys.

## Three more lanes on the escape helper, 2026-10-02

- **`knowledge:video-digest`, `harness-ops:observability` and `event-storming:simulation` build
  their HTML with a checked-in builder (#5846).** Each routes every interpolated external string
  (fetched transcripts and titles, telemetry strings, board text) through the synced
  `lib/html-escape.mjs` and stamps the generator marker. The two that were grandfathered
  (`harness-ops:observability`, `event-storming:simulation`) leave that list; the escape-helper
  lanes are named in the emitters paragraph of the README. No boundary-rule, genre, or
  cascade-key change.

## Escape helper, 2026-09-28

- **The wave-2 escape helper shipped (#3605).** `lib/html-escape.mjs` is the
  canonical copy, synced into each adopting plugin at `lib/html-escape.mjs` and
  drift-gated by `scripts/sync-html-escape.sh`. Emitted pages carry a generator
  marker that `validateRenderedPage` checks. `/review:pr-explainer` is the first
  lane on that gate. Existing carve-outs that still do not render another
  repository's files stay in place until those lanes are wired through the
  helper. No boundary-rule, genre, or cascade-key change.

## Template vendoring, 2026-09-28

- **Whole-page vendoring of the 31 html-effectiveness corpus templates is
  declined (#3608).** The derived chrome/token reference remains the sanctioned
  shared piece. Per-genre page-shape is a pointer to the public gallery. A
  future single-page vendor must name which source it took (gallery Apache-2.0
  headers vs `anthropics/html-effectiveness` MIT) and carry the matching
  notice. No boundary-rule, genre, or cascade-key change.
