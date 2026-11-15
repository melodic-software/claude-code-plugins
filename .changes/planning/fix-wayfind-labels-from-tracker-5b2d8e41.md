---
bump: patch
---

### Changed

- `/planning:wayfind` gets its label prefix and human-gated label from
  `/work-items:track wayfind-labels` and stops on its refusal, instead of finding and reading the
  tracker binding itself. It needs the work-items release that adds that action; with an older
  one it stops and asks for the plugin to be updated.
- The three wayfind label eval cases that scaffolded a binding file are replaced by five that
  supply the `/work-items:track wayfind-labels` reply, one of them a refusal and one an older
  release's action table, since an eval sandbox loads no other plugin.
