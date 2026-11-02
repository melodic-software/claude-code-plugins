---
bump: minor
---

### Added

- **Planning's other optional views honor the `rendered-views` `medium` preference.** The interview's read-only decision table, the PRD pitch view and the design topology view resolve `medium` from the request, then the `rendered-views` layers (`reference/rendered-view.md`, "Other optional views"). `terminal` writes no file: the interview renders the table inline, and the PRD and design steps skip the view. Every other value writes the local file as before.
