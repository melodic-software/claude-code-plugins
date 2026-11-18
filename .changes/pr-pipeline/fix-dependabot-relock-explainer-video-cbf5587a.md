---
bump: minor
---

### Added

- **`dependency-relock` patch row, a relock with no model turn.** When a Dependabot pip pull request
  for a `group-by: dependency-name` group bumps one of the entry's directories and leaves another,
  `review-dependency-select` uploads a relock request, `review-dependency-relock` runs the uv
  `.github/requirements-relock.txt` pins in a digest-pinned `python:3.12-slim` container with no
  permissions, `review-dependency-relock-patch`
  checks the relocked lock with base code, and `apply-dependency-relock` pushes it as a
  `[dependabot skip]` commit held to `dependency-version-change`. A relock that fails or is refused
  stops as `dependency-pin-invalid`, labelled `needs-session`; it does not go to the model. `dependency-relock.mjs check` fails `test-bash` while a group's
  directories disagree, when no pip group reads, or when a group directory's `requirements.in`
  cannot be read.
