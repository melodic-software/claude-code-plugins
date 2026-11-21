---
bump: patch
---

### Changed

- **The notes host page now reports a framed page that never says it is ready.** If the frame helper's first ready message has not arrived within 10 seconds, the host page says so, on a real-stack route and on a mockup alike. On a real-stack route it adds that the dev server may refuse to be framed or the route may not load the helper. It does not judge by the frame's load event. The new `notes-bridge/frame-channel.mjs` holds the host page's channel rules. A message is taken only from the frame's window and, on a real-stack route, from the dev origin. Every message to a real-stack frame names the dev origin as `targetOrigin` ([#17748](https://github.com/melodic-software/claude-code-plugins/issues/17748)).
