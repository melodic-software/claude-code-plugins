---
bump: minor
---

### Changed

- The Verifier verdict section says a capture the key cannot make records an advisory cause, `credit-stop`, `empty-key`, `probe-handoff` or `unrecognized`, each with its own reason, in place of the one fixed "subscription token cannot go behind the proxy" reason. The verdict's `evidence` carries that `cause`, and its `pr-verify capture` annotation names a blocked capture and its cause. While the credit gate skips the key, the capture job uploads that blocked capture instead of none. A credit stop on the probe's key raises the handoff warning naming the pr-verify role's key and the run.
