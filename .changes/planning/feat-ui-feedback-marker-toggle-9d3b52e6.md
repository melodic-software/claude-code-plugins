---
bump: patch
---

### Changed

- The shared page's `proto-pin.js` copy takes the ui-feedback frame helper's `markers` message, which a host sends to hide or show the note markers. The shared page never sends it, so its markers stay drawn as before ([#17802](https://github.com/melodic-software/claude-code-plugins/issues/17802)).
