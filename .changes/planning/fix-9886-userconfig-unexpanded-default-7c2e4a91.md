---
bump: patch
---

### Fixed

- `/planning:interview` reads a `userConfig` value that arrives as its unexpanded `${user_config.KEY}` token as that key's own default, never as off. A shared session with `shared_session_open_browser` never saved now opens the owner's page in the browser, as the default `true` says.
