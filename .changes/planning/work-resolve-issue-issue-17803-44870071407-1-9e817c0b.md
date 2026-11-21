---
bump: patch
---

### Changed

- **The shared page's copy of `proto-pin.js` picks up the move-arrow kind.** The frame helper now
  supports a `move` pick mode, which posts a move arrow with an anchor for each end and draws it.
  The shared page does not ask for that mode yet, so its pins behave as before.
  ([#17803](https://github.com/melodic-software/claude-code-plugins/issues/17803))
