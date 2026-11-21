---
bump: patch
---

### Changed

- The shared page's `proto-pin.js` copy takes the ui-feedback frame helper's opt-in hold: a host that sends `hold: true` with pick mode keeps the pick drawn until it sends `release`. The shared page sends neither, so its picks behave as before ([#17800](https://github.com/melodic-software/claude-code-plugins/issues/17800)).
