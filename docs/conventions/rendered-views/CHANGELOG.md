# Changelog for the Rendered Views Convention

Notable changes to the rendered-views contract. The contract is not SemVer-
versioned; this log records posture rulings that do not change the boundary
rule, genre rubric, or cascade keys.

## Template vendoring, 2026-09-28

- **Whole-page vendoring of the 31 html-effectiveness corpus templates is
  declined (#3608).** The derived chrome/token reference remains the sanctioned
  shared piece. Per-genre page-shape is a pointer to the public gallery. A
  future single-page vendor must name which source it took (gallery Apache-2.0
  headers vs `anthropics/html-effectiveness` MIT) and carry the matching
  notice. No boundary-rule, genre, or cascade-key change.
