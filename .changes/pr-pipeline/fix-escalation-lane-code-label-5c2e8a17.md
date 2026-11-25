---
bump: patch
---

### Fixed

- `report-escalation.sh` hold comments name the lane's stop code as `- Lane code: ...`, so `Reason:` names only the owner reason (`intent`, `design`, `security` or `cost`). Before, a hold showed two `Reason:` lines, such as `Reason: design` and `Reason: feedback-question-design`.
- A `feedback-question-*` hold lists the PR's open review threads, one of which holds the disputed finding the adjudicator left for a person, in a collapsed `<details>` block.
- Hold comments follow the lane output format: a `pr-unblock / report-escalation` heading, a `Held for a person:` verdict line, at most three bullets (lane code, resume key, how to resume), and any thread list collapsed at the end.
- `gate-source.mjs` and `clear-escalations.mjs` read the lane code from either label, so hold comments already open with `- Reason:` keep their meaning, and a re-run of the same hold on the same head still posts nothing.
