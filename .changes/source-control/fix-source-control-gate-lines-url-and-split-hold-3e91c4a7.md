---
bump: patch
---

### Fixed

- `/source-control:pull-request`: `scripts/check-gate-lines.sh`, the attended body refresh's gate-line comparison, also counts a closing keyword followed by a full issue URL, and hold wording whose words sit on two lines (one `hold wording across lines:` entry per match), so a refresh can no longer add, drop or change either unnoticed.
