---
bump: minor
---

### Added

- The `skip-reason` enum gains `owned-branch`. pr-unblock's fix-ci select job posts it on a pull request whose head branch `merge.refire-skip-branches` lists, and the fix-ci dispatcher never dispatches such a pull request. The workflow that owns the branch rebuilds it, and the rebuild is the branch's fix: on release PR #11840, `release-publish-plugins.yml` moved `release/plugins` after fix-ci read it, so every fix-ci push answered 422.

### Fixed

- `apply-patch.mjs` puts GitHub's answer in the error when a REST call fails: the JSON body's `message` and `errors`, or the body text. The token and any credential-shaped text are redacted, control characters are dropped, and the text is capped at 500 characters. A failed ref update used to log only `returned 422`.
