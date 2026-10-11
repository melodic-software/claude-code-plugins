---
bump: minor
---

### Changed

- `pull-request ready` hands the pull request to `/review:explain-change` with `--event ready` right after the flip, so the `digest_policy` setting takes effect on the pushed head: `off` does nothing, `offer` offers the digest when a trigger fires, and `always` builds it. The digest gates nothing.
