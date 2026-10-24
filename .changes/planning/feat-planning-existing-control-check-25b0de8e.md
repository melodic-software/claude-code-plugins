---
bump: minor
---

### Added

- `/planning:plan` and `/planning:interview` name, before presenting a plan step or an option that adds a mechanism (a branch, workflow, ruleset, app, service, dependency or check), the existing control that already covers the same risk, and say whether they read its enforcing source or only a document. They drop the mechanism, or recommend dropping it, when such a control exists. A security control is never dropped without the user's decision. An abstraction for a stated, known repetition stays when it passes the standards index's `reference-dont-duplicate` tests. A non-trivial new mechanism goes to `/overengineering:justify` on the proposal. One interview eval case covers each side.
