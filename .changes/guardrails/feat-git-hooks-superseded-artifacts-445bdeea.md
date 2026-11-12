---
bump: minor
---

### Added

- The git-hook installer finds what an install under an earlier plugin name left: copies, `<event>.d/` markers, lefthook jobs, config-hook copies and keys, and decline keys. `verify` reports them as `superseded` drift, a decline under the earlier name still counts as declined, and `plan` returns them as a `superseded` decision that `apply install-git-hooks` removes on the user's yes, carrying a decline over to this plugin's key.
