---
bump: minor
---

### Added

- The interview page has a `Someone else decides` choice: a deferral whose note names the person who holds the decision. The summary lists these, and at wrap-up they are the person-held deferrals `/planning:interview` routes to `/planning:questionnaire`.

### Fixed

- The interview page's answer area no longer starves the question: the question keeps at least half the pane (or 18rem), every choice shows without its own scroller, the answer grid stays two columns down to 900 px, and Save stays in view.
- At phone width the interview page shows the current question before the question list, and a pick from the list scrolls its question into view.
- The interview surface reference no longer offers `/planning:wayfind` at wrap-up; it names wayfind only where the skill does.
