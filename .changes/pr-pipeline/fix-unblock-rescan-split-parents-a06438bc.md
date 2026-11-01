---
bump: patch
---

### Fixed

- The work-unblock sweep rescans open split parents whose sub-issues are all completed, on their UTC hour (number modulo 24) and at most `limits.parent-rescan-per-run` (new, default 5) per run, under the same close rules, so a parent whose last sub-issue closed outside the sweep window still closes and one that stays open logs why. The rescan and the `status: ready` readmission share one listing of open issues.
