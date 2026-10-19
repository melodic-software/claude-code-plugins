---
bump: patch
---

### Fixed

- `continue-in-background` launches the `claude --bg` session with `--permission-mode auto`, so a permission ask no longer waits for an attach while the user is away. The launch report says auto mode may deny an action and that where a denied action is reported is unverified.
