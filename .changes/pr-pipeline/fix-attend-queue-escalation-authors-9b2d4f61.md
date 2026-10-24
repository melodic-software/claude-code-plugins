---
bump: patch
---

### Fixed

- report-outcome's hand-backs (pushback, stopped, a refused patch, a dimension skip and a turn cap with no restart left) open with `<!-- work-items:escalation lane=work-resolve-issue kind=escalated -->`, then the outcome marker, so `/work-items:attend-queue` lists the issue as escalated. The outcome-marker parser that `issue-prior`, work-unblock and the monitor signals share reads the outcome marker after that one line.
