---
bump: patch
---

### Removed

- The hold floor drops its `.github/scripts/intake-triage/triage-rubric.txt` row: the file is deleted, since `/work-items:triage --ci` reads `## Triage rules` in `docs/conventions/work-items.md` and no lane passes the rubric to a model.
