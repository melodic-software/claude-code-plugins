---
bump: minor
---

### Changed

- **The CI code-review and security-review lanes converge across rounds.** After the first round each reviews only the new diff, never reposts a finding it already posted, names a repeated mistake as one class with every instance, and stops adding findings after three rounds: the code lane then asks a person to decide, and the security lane still reports a new CRITICAL or IMPORTANT finding.
