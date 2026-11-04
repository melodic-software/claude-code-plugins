---
bump: patch
---

### Changed

- The `quality-gate` PR mode no longer states what the `code-review` marketplace plugin targets
  or where its findings go; it keeps the plugin gated and points at the plugin's Commands section
  and the local review's reads-and-edits section.
- The `security-review` bundled-command record no longer lists what gates the native command;
  it keeps that the lane never depends on it and points at the commands reference.
