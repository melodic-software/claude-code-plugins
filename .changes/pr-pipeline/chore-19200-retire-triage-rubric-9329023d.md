---
bump: patch
---

### Changed

- The hold floor's `.github/scripts/intake-triage/triage-rubric.txt` row becomes a `gate` row for `docs/conventions/work-items.md`: the rubric file is deleted, and `/work-items:triage --ci` reads that file's `## Triage rules`, so a person still approves any change to the intake lane's triage rules.
