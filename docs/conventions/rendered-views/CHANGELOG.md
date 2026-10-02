# Changelog for the Rendered Views Convention

Notable changes to the rendered-views contract. The contract is not SemVer-
versioned; this log records posture rulings that do not change the boundary
rule, genre rubric, or cascade keys.

## Generated helper copies, 2026-10-02

- **Each adopting plugin's `lib/html-escape.mjs` is generated output (#5836).**
  `scripts/sync-shared-copies.sh` writes it from the canonical with a generated-file
  header and drift-gates it, replacing `scripts/sync-html-escape.sh` (ADR 0019,
  amended). No boundary-rule, genre, or cascade-key change.

## Sharing claim and chrome background, 2026-10-02

- **The sharing paragraph records the repository decision plus a pointer**, an as-of date and a
  recheck trigger, in place of the earlier "verified absent" claim. It states no upstream text.
- **The chrome's ivory background is the sanctioned default.** No skill's styles-to-leave-out
  list names a cream or off-white background; those lists name layout habits. Carve-outs for
  pull-request diffs, fetched content and other repositories' files now read "until the lane is
  wired through the escape helper", not "until the helper ships". No boundary-rule, genre, or
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
