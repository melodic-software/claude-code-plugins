---
bump: minor
---

### Added

- `block-unresolved-pr-merge` takes the trusted-actor list it judges pr-verify's scope with from the `<owner>/<repo>` that `standards_repository` names (`components/trusted-actors/trusted-actors.json`, at its `main` branch tip, read once by the full ref `refs/heads/main` so a tag named `main` cannot stand in) when the base branch's `docs/conventions/source-control.yaml` sets `trusted_actors_source: standards`. Without that key, or with `repository`, it reads the repository's copy as before; any other value, `standards` with no valid `standards_repository`, or a standards read that fails, lets the merge run unchecked with a warning, as other failed reads do.
