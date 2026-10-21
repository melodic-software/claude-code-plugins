---
bump: minor
---

### Added

- **`/session-flow:orient catch-up` answers "what happened since my last message, and what needs me"** ([#8640](https://github.com/melodic-software/claude-code-plugins/issues/8640)). The reply opens with a "Needs you" section (the count of decisions only the user can make), then what happened with what it means, then each decision with why now, options and costs, a recommendation, what happens if unanswered, and what is unknown. It anchors at the user's own last message and re-checks the pull requests, CI runs and agents the chat touched, read-only. The four-part briefing stays the default scope. A new `orient_catch_up_word_cap` setting caps the reply (default 250, minimum 150). Adapted from the pstack [`ketchup`](https://github.com/cursor/plugins/tree/88d47514b82e7c44f00f2b2a72ff6dd12158038c/pstack/skills/ketchup) skill.
