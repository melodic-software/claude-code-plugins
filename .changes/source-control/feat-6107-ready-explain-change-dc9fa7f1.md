---
bump: minor
---

### Changed

- `pull-request ready` hands the pull request to `/review:explain-change` with `--event ready` before the flip, so the `digest_policy` setting takes effect: `off` does nothing, `offer` offers the digest when a trigger fires, and `always` builds it. The digest gates nothing, and the flip runs whatever it returns.
