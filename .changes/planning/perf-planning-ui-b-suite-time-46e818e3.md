---
bump: none
---

Splits the shared page's `ui_layout.js` browser suite in two, its phone-keyboard checks moving to
`ui_layout_keyboard.js`, so part b of the browser suites runs under the per-suite time budget.
Every check still runs. No plugin behavior changes.
