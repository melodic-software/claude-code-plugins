---
bump: minor
---

### Added

- `loosened-check-settings.mjs` reads the trusted-actor list from the `<owner>/<repo>` that `standards_repository` names (`components/trusted-actors/trusted-actors.json`, at its `main` branch tip, read once by the full ref `refs/heads/main` so a tag named `main` cannot stand in) when the default branch's `docs/conventions/source-control.yaml` sets `trusted_actors_source: standards`, and names that repository and commit in `loosened_check_spec`. Without that key, or with `repository`, it reads the repository's copy as before; any other value, `standards` with no valid `standards_repository`, or a standards read that fails, prints `no reason`.
