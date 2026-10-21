---
bump: minor
---

### Added

- **New checks: `browser-extensions` and `network-listeners`.** The audit now lists every Chrome, Edge and Firefox extension plus the browsers' forced-install policies, and every listening port with the program that owns it; each entry can be muted, and unpacked, sideloaded or high-permission extensions and exposed unsigned listeners raise a warning.
