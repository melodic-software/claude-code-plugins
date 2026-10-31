---
bump: patch
---

### Fixed

- When every answer was accepted as recommended or confirmed after its read-back, `/planning:interview`'s final confirmation no longer re-lists the unchanged accepted answers, even at the first confirmation. A recap saved once each round's read-backs are confirmed lets the pasted `--changed` recap list only the answers changed since, and the restatement adds the intent, the hedged answers and the assumptions the user has not seen. A host run of the `interview-final-brief-changes-only` eval case on 2026-10-30 scored 0 of 3 with-plugin runs on its changes-only and omits-unchanged graders before this rule.
