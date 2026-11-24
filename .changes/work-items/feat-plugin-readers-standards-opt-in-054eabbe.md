---
bump: minor
---

### Added

- The GitHub adapter's `config.github.status_trust.trusted_actors` accepts `standards:<owner>/<repo>:<path>`: `get-statuses` then reads the trust list at `<path>` in that repository, at its `main` branch tip, read once per run by the full ref `refs/heads/main` so a tag named `main` cannot stand in, for every item repository. A repo-relative path reads each item repository's copy as before.
