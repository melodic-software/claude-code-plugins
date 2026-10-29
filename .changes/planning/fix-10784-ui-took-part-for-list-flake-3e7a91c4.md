---
bump: none
---

Fixes a flaky step in the `ui_took_part.js` browser test. The step ticks Bo in a question's "who must answer" list.
It now waits for the list to show Bo, then clicks the box and waits for the server to record it. It no longer calls
`check()`, which throws when a state poll re-renders the box between the click and the read. No skill, script or
setting the plugin ships changes.
