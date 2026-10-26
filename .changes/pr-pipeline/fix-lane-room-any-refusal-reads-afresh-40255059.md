---
bump: patch
---

### Fixed

- `enable-auto-merge` no longer leaves every lanes App pull request unarmed, and disarms the armed ones, when the run's post-merge report is one the gate would not reuse (for example `demotion-changed`, which any issue the lanes App files and triage then labels sets). The lane's room now checks the report again as the gate does and arms from that answer.
