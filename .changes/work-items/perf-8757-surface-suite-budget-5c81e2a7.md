---
bump: patch
---

### Changed

- The view bridge's `session_bridge.py` copy has a new `reading_window()` app hook from the shared session-bridge library. It sets how long after a delivery the listener reports `reading`. The default is still 180 seconds and this plugin does not override it, so its behavior is unchanged ([#8757](https://github.com/melodic-software/claude-code-plugins/issues/8757)).
