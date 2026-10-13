---
bump: minor
---

### Added

- The interview page has a `Someone else decides` choice: a deferral whose note names the person who holds the decision. The summary lists these, and at wrap-up of an engineering session `/planning:interview` counts them with the person-held deferrals it routes to `/planning:questionnaire` (if enabled).

### Fixed

- The interview page's answer area no longer starves the question: the question keeps at least half the pane (or 18rem), every choice shows without its own scroller when the pane has room, the answer grid stays two columns down to 900 px, and Save stays in view at every width.
- At phone width the interview page shows the current question before the question list, and a pick from the list scrolls its question into view.
- The interview surface reference no longer offers `/planning:wayfind` at wrap-up; it names wayfind only where the skill does.
