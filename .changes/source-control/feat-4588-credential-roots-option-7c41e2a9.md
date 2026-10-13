---
bump: minor
---

### Added

- `babysit-loop`'s promotion-evidence helper passes the checker `--credential-roots` from a new optional option, `promotion_evidence_credential_roots` (#4588). The helper reads it from managed or user settings like the other four. Unset, the checker gets no flag, as before. Set, each comma-separated entry must be absolute, not a filesystem root, free of `..` segments and outside the checkout and every worktree root, judged as text because the paths name the probe host; a bad entry fails closed under a reason naming it. The unattended merge gate checks only that the settings file holding the value is not lane-writable, never the value itself.
