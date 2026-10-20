---
bump: minor
---

### Added

- The interview surface has a `revising-by-claude` op: Claude marks a set of questions as being revised, with a reason, and the page shows "Claude is revising this: <reason>" on each question's rail card and detail pane. The mark informs only, so answering stays possible. A `revise` or `reply` of a question, or an explicit `clear`, removes it.
- A revision that lands on the selected question while a choice is armed or a note is typed now shows the "Qn just changed: review" notice at once, instead of only when Save returns a 409.
