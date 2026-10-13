---
bump: patch
---

### Security

- `babysit-loop`'s promotion-evidence helper (`resolve-promotion-evidence.mjs`) now refuses a surface, checker or supplying settings file the lane user can write, or owns, at the path or any directory above it, as given or after symlinks resolve, failing closed as `lane-writable:<option or file>` (#4588). Before, only the unattended merge gate checked this, so the babysit-loop prose route resolved promotion from user-owned surfaces. On Windows, where the check cannot read an ACL, the helper fails closed on every call as `writability-unverifiable-on-win32`. The merge gate keeps its own check as a second layer. Credential roots name the probe host, so only the settings file that set them is checked.
