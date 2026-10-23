---
bump: patch
---

### Changed

- The HIGH path floor holds only the takeover set: `.github/standards/trusted-actors/**`, `.github/actions/check-trusted-trigger/**`, `**/CODEOWNERS`, `**/.gitmodules` and `.github/actions/resolve-config/**`. Agent permission config (`**/settings*.json`), package manifests and lockfiles, and every workflow, `release-*.yml` included, leave it and merge on the review lanes. With the floor on, any change under the trusted-actor directory scores HIGH, a pure list removal included. The cost hold and the outside-author hold are unchanged.
- `own_paths` leaves out only `NEVER_FLOOR_EXEMPT` (the floor), so a trusted author's own `settings*.json`, package manifest and `requirements*.txt` lines are its own. `INSTRUCTION_PATH_RE` and its twin test are gone; `thread-scope.mjs` `INSTRUCTION_PATH`, which bounds pr-unblock's fix scope, is unchanged.
