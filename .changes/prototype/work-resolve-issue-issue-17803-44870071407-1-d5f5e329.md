---
bump: minor
---

### Added

- **A move-arrow note says "move this element to there" on the mockup.** On the notes host page,
  Draw a move arrow (M) picks the element to move, then the element it should go to (or, with
  Shift and a click, a point when no element fits), then opens the note. The frame draws the arrow
  from one end to the other and redraws it from the elements when the page re-flows. The note's
  `kind` is `move`: `anchor` and `rect` are the element to move, and the new `to` field holds the
  destination's `point` and, when there is one, its `anchor`. The note schema's `x-version` moves
  to 6. `relocate-note.mjs` runs the anchor ladder on both ends and reports the destination under
  `to`. explore-directions restates both ends of a move arrow before acting on it.
  ([#17803](https://github.com/melodic-software/claude-code-plugins/issues/17803))
