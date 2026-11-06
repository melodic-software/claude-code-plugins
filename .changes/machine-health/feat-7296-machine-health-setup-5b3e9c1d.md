---
bump: patch
---

### Fixed

- `/machine-health:setup` hands over the `plugin configure` and `plugin install` commands with `<marketplace>` left as written unless the owner named the marketplace, and no longer searches manifests, the plugin cache or settings for the name.
