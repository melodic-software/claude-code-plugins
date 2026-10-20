---
bump: minor
---

### Added

- **The interview page searches and jumps to a question.** A search box in the rail toolbar matches the question id, short title and title: typing words filters the rail, and typing a number then Enter opens that question (`100` opens Q100). It narrows within the Show filter, and the rail says when Show hides matches. A jump opens the group that holds the question. Selecting a question writes `#<id>` to the URL (replacing the hash, so Back still leaves the page), and loading or changing to `#Q100` selects Q100; an unknown id leaves the selection alone. (#5915)

### Changed

- **`/` now focuses the new search box, and `s` focuses the Show filter.** The keyboard sheet lists both. (#5915)
- **A rail button's accessible name is its id, short title and state.** The needs chips, state chips and Claude preview move to its accessible description. (#5915)
