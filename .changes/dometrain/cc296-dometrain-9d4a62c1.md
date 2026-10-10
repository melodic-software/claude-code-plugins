---
bump: patch
---

### Changed

- **The headless install adds the marketplace and installs in one step at `user` scope.** `/dometrain:setup`'s scripted install now uses `claude plugin install <plugin> --marketplace <source>` when the bootstrap installs at `user` scope on a CLI that supports it, which drops the separate `marketplace add` step. At `project` or `local` scope, or on an older CLI, it keeps the two-step form so the marketplace is registered in the same scope as the install. A pointer to the plugin commands reference says where to check the flag's minimum version and where the one-step form registers the marketplace. The README's install lines for Dometrain's own plugin show the same one-step form with the two-step fallback.
