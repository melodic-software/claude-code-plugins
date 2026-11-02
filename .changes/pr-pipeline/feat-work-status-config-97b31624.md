---
bump: minor
---

### Added

- `models.issue-status` names an issue's state as its Work status org issue field: the field id, each option id's state, the labels each state collapses from, and the collapse order (first match wins, labels compared without case; no state label collapses to the last, `needs-triage`). The config reader rejects two options for one state, a state with no label, a label listed twice, an order that does not list every state once or does not end on `needs-triage`, and a field id `models.issue-dimensions` uses (`undefined-status`). resolve-config's new `issue-status.mjs` exports `collapseStatus` (an issue's labels to its state), `statusOption` (a state's option id) and `issueStatus` (the state the field holds under the issue-dimensions setter rule, or null; an unmapped option fails with `unmapped-status`); `dimensions.mjs` exports the shared `trustedOption` reader. No lane reads or writes the field yet.
