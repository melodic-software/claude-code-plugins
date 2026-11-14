---
bump: patch
---

### Changed

- `/planning:wayfind` gets its label prefix and human-gated label from
  `/work-items:track wayfind-labels` and stops on its refusal, instead of finding and reading the
  tracker binding itself.
- The three wayfind label eval cases that scaffolded a binding file are replaced by four that
  supply the `/work-items:track wayfind-labels` reply, one of them a refusal, since an eval
  sandbox loads no other plugin.
