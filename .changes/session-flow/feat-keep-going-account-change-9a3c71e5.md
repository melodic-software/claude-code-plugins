---
bump: minor
---

### Added

- keep-going names the active account (read from `claude auth status`) and the account at the time of a rate-limit stop, and reports changed, unchanged or unknown with the source of each reading, so a captured limit message is not read against a different account. When either identity cannot be established, it reports unknown and asks the operator.
