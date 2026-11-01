---
bump: patch
---

### Changed

- The `/ai-slop:audit` description names commit messages, PR bodies, interface copy and generic headlines beside markdown, and sends code-comment requests to `/code-tidying:audit-comment-residue`. Measured before and after on the frozen probes and a blind held-out set (Opus 5.5, every run VALID): no lost trigger, and held-out triggering rose from 58% to 83%.
