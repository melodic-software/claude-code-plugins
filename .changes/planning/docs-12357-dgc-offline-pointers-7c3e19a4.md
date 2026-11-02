---
bump: patch
---

### Changed

- `draft-goal-condition`: the workflow-row caveat no longer restates where the `ultracode` keyword starts a workflow or which plans reach dynamic workflows. It points at the new `reference/workflow-row.md`, which keeps each as a routing decision with its pointer, as-of date (2026-11-02) and recheck trigger, so the skill still routes when the docs pages cannot be fetched (#12357). Measured on `dg-workflow-keyword-unattended` before and after: 1, 1, 1 both, all runs VALID. The `xhigh` condition on `/effort ultracode` stays in the skill body: its move did not pass the preregistered measurement. A new case, `dg-standing-setting-xhigh`, covers it.
