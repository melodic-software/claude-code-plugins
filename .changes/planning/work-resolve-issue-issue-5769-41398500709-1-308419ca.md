---
bump: minor
---

### Added

- The interview page shows a recommended answering order once more questions are open than the new `orderThreshold` setting (default 25). The header's Answering order panel lists the open questions with prerequisites first (topological by `dependsOn`), then the most transitive dependents, then the lower id. At or below the threshold the page is unchanged. The order is advisory and changes no `frontierLock` check (#5769).

### Changed

- `/planning:interview` Step 3 and the loop's gate list name the `stale=<n>` verdict of `check-open-questions.sh` as a halt. The constraint ledger's Re-check now covers answered rows as well as open ones (#5769).
