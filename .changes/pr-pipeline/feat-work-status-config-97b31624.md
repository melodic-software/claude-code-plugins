---
bump: minor
---

### Added

- `models.issue-status` names an issue's state as its Work status org issue field: the field id, each option id's state, the label each state collapses from, and the collapse order (first match wins; no state label collapses to the last). The config reader rejects two options for one state, a state with no label or one shared with another state, and an order that does not list every state once (`undefined-status`). resolve-config's new `issue-status.mjs` exports `collapseStatus` (an issue's labels to its state), `statusOption` (a state's option id) and `issueStatus` (the state the field holds, or null; an unmapped option fails with `unmapped-status`). No lane reads or writes the field yet.
