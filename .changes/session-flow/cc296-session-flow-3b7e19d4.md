---
bump: patch
---

### Fixed

- **`/session-flow:handoff` no longer requires task tools the session may not have.** The handoff mandated a live `TaskList` call and `TaskCreate`/`TaskUpdate` recreate lines, but current models do not get the task-tracking tools by default, so the save-point failed or improvised on them. It now branches on whether the tools are present in the session: with them it captures the live list as before; without them it writes a line saying so and points at the workflow checklist or plan it already keeps. A resuming session without the tools reads the recorded list instead of running the recreate calls. The position panel's task-list rung falls through the same way.
- **`/session-flow:workflow` tracks stages without the task tools.** Stage tracking used `TaskCreate` unconditionally; it now does so only when the tools are present and otherwise uses the `workflow-checklist.md` file (or the plan that replaces it) as the tracker.
