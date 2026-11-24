---
bump: minor
---

### Added

- `block-unresolved-pr-merge` takes the trusted-actor list it judges pr-verify's scope with from `melodic-software/standards` (`components/trusted-actors/trusted-actors.json`, at the main commit it resolves once) when the base branch's `docs/conventions/source-control.yaml` sets `trusted_actors_source: standards`. Without that key, or with `repository`, it reads the repository's copy as before; any other value, or a standards read that fails, lets the merge run unchecked with a warning, as other failed reads do.
