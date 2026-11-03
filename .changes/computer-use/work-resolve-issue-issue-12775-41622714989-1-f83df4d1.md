---
bump: patch
---

### Changed

- The README and `diagnose` no longer explain how screenshots are downscaled; they keep `zoom`
  as the lever and point at the computer-use page's downscaling section.
- `setup` no longer states what `list_granted_applications` returns, what `request_access` shows,
  or the allowlist gate's error text. It keeps the probe choice and the rule never to call
  `request_access` during a check, with pointers to the tool listing and the approval section.
  The idle-timer statement and the gate's refusal now read as this plugin's own Windows
  measurements and link the diagnostics reference that records them.
