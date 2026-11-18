---
bump: minor
---

### Added

- **`dependency-relock` patch row, a relock with no model turn.** When a Dependabot pip pull request
  for a `group-by: dependency-name` group bumps one of the entry's directories and leaves another,
  `review-dependency-select` relocks the lagging directory to the bumped pin with the uv
  `.github/requirements-relock.txt` pins, and `apply-dependency-pin` pushes it as a
  `[dependabot skip]` commit held to `dependency-version-change`. A relock that fails goes to the
  model, and `dependency-relock.mjs check` fails `test-bash` while a group's directories disagree.
