---
bump: minor
---

### Added

- The git-hook installer finds what an install under an earlier plugin name left: copies, `<event>.d/` markers, lefthook jobs, config-hook copies and keys, and decline keys. `verify` reports them as `superseded` drift, a decline under the earlier name still counts as declined, and `plan` returns them as a `superseded` decision that `apply install-git-hooks` removes on the user's yes, carrying this clone's resolved decline or opt-in to this plugin's key in its local config. A decline line under the earlier name in a system or global config file is reported with the command to remove it, never edited, since other clones may rely on it.
