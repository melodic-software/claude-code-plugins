---
bump: patch
---

### Fixed

- **`/code-tidying:batch-simplify` tracks its groups on models without the task tools.** Phase 5 told Claude to create one `TaskCreate` task per group and track it with `TaskUpdate`, but current models do not get the task-tracking tools by default, so the tracking step had no tool to call. Phase 5 and Phase 6 now use the task tools when the session has them and otherwise track each group as an entry in the run's copied checklist, and the skill points at the live docs section that says which sessions get the tools.
