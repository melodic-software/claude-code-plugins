---
bump: patch
---

### Fixed

- `block-root-delete-target` drops a `/` entry in `block_root_delete_target_allowed_roots`, or a name-prefix entry whose directory is `/`, on every host. Under Git Bash `/` maps to the Git install directory, so the entry was kept and allowed a recursive delete of every path under that directory, such as `/opt/...`.
