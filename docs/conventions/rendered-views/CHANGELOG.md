# Changelog for the Rendered Views Convention

Notable changes to the rendered-views contract. The contract is not SemVer-
versioned; this log records posture rulings that do not change the boundary
rule, genre rubric, or cascade keys.

## Escape helper, 2026-09-28

- **The wave-2 escape helper shipped (#3605).** `lib/html-escape.mjs` is the
  canonical copy, synced into each adopting plugin at `lib/html-escape.mjs` and
  drift-gated by `scripts/sync-html-escape.sh`. Emitted pages carry a generator
  marker that `validateRenderedPage` checks. `/review:pr-explainer` is the first
  lane on that gate. Existing carve-outs that still do not render another
  repository's files stay in place until those lanes are wired through the
  helper. No boundary-rule, genre, or cascade-key change.

## Reports and research offer lanes, 2026-09-28

- **`education:explain` and `testing:audit` offer HTML views (#3606).** Research
  and concept explainer, and report. Offer, not emit: the markdown record stays
  the deliverable. Each lane names its genre and stays inside the 40-line
  budget. The escape helper gains education and testing as adopters. No
  boundary-rule, genre-list, or cascade-key change.

## Interactive userConfig smoke test, 2026-09-28

- **Parked until a CLI host funds the interactive smoke (#3604).** The
  visualization `medium` dial's set / persist / clear path stays unrun. The
  unset path remains the documented literal-token behavior. This park keeps
  gating the grandfathered-surface fleet sweep (#3603). No boundary-rule,
  genre, or cascade-key change.

## Template vendoring, 2026-09-28

- **Whole-page vendoring of the 31 html-effectiveness corpus templates is
  declined (#3608).** The derived chrome/token reference remains the sanctioned
  shared piece. Per-genre page-shape is a pointer to the public gallery. A
  future single-page vendor must name which source it took (gallery Apache-2.0
  headers vs `anthropics/html-effectiveness` MIT) and carry the matching
  notice. No boundary-rule, genre, or cascade-key change.
