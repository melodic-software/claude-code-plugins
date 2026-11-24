---
bump: minor
---

### Added

- `trusted_actors_source: standards` in a repository's `docs/conventions/source-control.yaml` makes the babysit merge gate, the pr-verify evidence reader, the skip-unchanged key and the `ready` hold check read the trusted-actors list and the Dependabot policy from `melodic-software/standards` at one commit per process, instead of the repository's `.github/standards/` copies. Unset or `repository` reads the copies as before; any other value reads neither, so the lane adopts nothing and the hold check leaves the label holding.
