---
bump: minor
---

### Changed

- **`continue-in-background` launches only with a checkable completion condition** ([#8739](https://github.com/melodic-software/claude-code-plugins/issues/8739)). The launch payload is now `/goal` plus the save-point's goal region, so the detached session works until a fresh evaluator confirms the condition. With no goal applying, the skill drafts one with `/planning:draft-goal-condition`, shows it, and launches only once the user confirms. With no checkable condition it does not launch and says how to supply one. On prompt-only the resume region travels after the goal region, within the condition limit.
- **The `workflow` continuation router's away-from-keyboard brief carries a checkable completion condition** (`/goal` or a Stop-hook check).
