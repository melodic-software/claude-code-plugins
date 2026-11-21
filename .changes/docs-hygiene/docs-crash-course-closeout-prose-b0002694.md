---
bump: patch
---

### Changed

- `write-for-agents` counts context load as attention as well as tokens, and adds a placement rule: a procedure with a predictable trigger goes behind a pointer that names it, while triage keyed to an error symptom stays on the always-loaded surface.
- `compare-labeler` sets `omitClaudeMd: true`: the compare prompt carries the labels and output format, so it starts without the CLAUDE.md files.
