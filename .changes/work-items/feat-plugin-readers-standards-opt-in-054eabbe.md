---
bump: minor
---

### Added

- The GitHub adapter's `config.github.status_trust.trusted_actors` accepts `standards:<path>`: `get-statuses` then reads the trust list at `<path>` in `melodic-software/standards`, at the main commit it resolves once per run, for every item repository. A repo-relative path reads each item repository's copy as before.
