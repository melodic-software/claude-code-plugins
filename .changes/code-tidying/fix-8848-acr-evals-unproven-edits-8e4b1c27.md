---
bump: patch
---

### Fixed

- `dissolve-comments` now demotes an edit to a proposal when `change-shape.sh` returns UNAVAILABLE or no verdict, and the gate covers shell edits such as `sed -i` as well as Edit calls. `reference/safety.md` no longer lets a pygments-level read apply deletions without the proof.
- The `acr-readonly-strip-request` eval now invokes `/code-tidying:audit-comment-residue` by name. A bare strip request correctly routes to `dissolve-comments`.
- The `acr-dir-batch-skips` graders accept a total given as "2 comments to delete", and a NOTES.md that is named as skipped and then described on another line. `batch-total` still rejects a miscount of 3 files.
