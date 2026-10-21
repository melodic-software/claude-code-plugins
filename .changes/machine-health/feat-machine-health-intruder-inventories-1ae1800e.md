---
bump: minor
---

### Added

- **New checks: `browser-extensions`, `network-listeners` and `firewall-rules`.** The audit now lists every Chrome, Edge and Firefox extension plus the browsers' forced-install policies, every listening port with the program that owns it, and the inbound allow firewall rules that did not ship with Windows, noting rules whose program is gone; each entry can be muted, and unpacked, sideloaded or high-permission extensions and exposed unsigned listeners raise a warning, while firewall rules stay informational.
