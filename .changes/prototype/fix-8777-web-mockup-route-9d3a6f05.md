---
bump: patch
---

### Fixed

- `/prototype:explore-directions`: for an existing app, the skill now finds the app's design system before the plan, and in a redesign treats it as the baseline the variants depart from. It reuses what `/user-interface:design` found when that skill handed off earlier in the conversation, otherwise runs that skill's detection steps when it is installed, and otherwise reads the project's design files itself.
