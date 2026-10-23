---
bump: patch
---

### Changed

- pr-merge.yml's merge job runs its read-only post-merge check under the job's own `GITHUB_TOKEN` (the job gains `issues: read` for the demotion records) instead of the lane App token; only the `--remediate` run keeps the lane token. The gate's review-evidence reads run under `BABYSIT_VERIFY_GH_TOKEN` too, so the lane token is spent on writes and the reads that need the App's identity.
