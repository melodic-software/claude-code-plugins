---
bump: minor
---

### Added

- The pr-verify evidence reader refuses a pass `verify:spec-changed` when the repository reads its trusted-actors list from standards (`trusted_actors_source: standards`) and the list changed since the pass judged it: the verdict's `trusted_actors_blob` is not the git blob id of the live standards list. A pass that records no blob still counts while the repository's `.github/standards/trusted-actors/` copy is at the branch tip, and is refused once that copy is gone. A repository that reads its copy compares no blob.
