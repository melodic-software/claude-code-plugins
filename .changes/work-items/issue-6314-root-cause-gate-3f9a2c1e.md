---
bump: minor
---

### Added

- The Agent Brief template gains a bug-only `Root cause` field (`unknown` or `known: <cause>`). `/work-items:triage` writes it when it briefs a bug, and `/work-items:work` runs `/debugging:debug` (or `/testing:diagnose` for a failing test) before implementing when it reads `unknown`; a named cause or a brief without the field goes straight to the fix.
