---
bump: minor
---

### Added

- `/session-flow:step-away` arms a session to run while you are away: prompts are refused and listed in a return report, your decisions are parked with options and a recommendation, and the report is shown once when you are back.
- session-flow now registers PermissionRequest, Elicitation, Stop and UserPromptSubmit hooks in every session; each does nothing unless a step-away absence is active.
- `/session-flow:go-with-recommendations` accepts the latest recommendations after a full evidence check, returning any that changed with old, new and why.
