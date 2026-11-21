---
bump: patch
---

### Changed

- The shared page's `proto-pin.js` copy accepts the ui-feedback frame helper's new `show` and `select` messages, which draw a listed note's box, and lets a host turn on marker clicks. The shared page sends none of these, so its markers still take no click and its pages behave as before ([#17801](https://github.com/melodic-software/claude-code-plugins/issues/17801)).
