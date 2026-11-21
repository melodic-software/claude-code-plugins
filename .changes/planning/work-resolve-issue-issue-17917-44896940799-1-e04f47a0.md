---
bump: patch
---

### Changed

- The shared frame helper `shared/web/proto-pin.js` also posts a `key` message when the person presses P, R, A, M or N inside the framed page and the page does not handle the key. The planning page ignores the message; the prototype notes host uses it to run its shortcuts ([#17917](https://github.com/melodic-software/claude-code-plugins/issues/17917)).
