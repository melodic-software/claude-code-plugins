---
bump: minor
---

### Added

- `loosened-check-settings.mjs` reads the trusted-actor list from `melodic-software/standards` (`components/trusted-actors/trusted-actors.json`, at the main commit it resolves once) when the default branch's `docs/conventions/source-control.yaml` sets `trusted_actors_source: standards`, and names that commit in `loosened_check_spec`. Without that key, or with `repository`, it reads the repository's copy as before; any other value, or a standards read that fails, prints `no reason`.
