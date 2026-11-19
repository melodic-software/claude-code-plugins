---
bump: minor
---

### Changed

- The git-hooks remote plan names the git URL of the marketplace the plugin was installed from (its GitHub or git source), so a fork's install fetches the fork; the publisher URL in `entries.json` stays the default when the marketplace has no such source.
