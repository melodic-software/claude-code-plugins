---
bump: minor
---

### Changed

- `control-claude-code`'s `cli/account.mjs` prints `none: API-key auth has no signed-in account` and exits 0 when `claude auth status` reports API-key auth with no email and no organization, so drive's mask post-check can resolve the `values:` source to no values. Any other auth with no account still exits 1.
