---
bump: patch
---

### Changed

- `pr-review-hosted.yml` and `pr-review-security-hosted.yml` call ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/6d6cb798e7cb7560a0f9327d8a22398961c23b31/.github/workflows/pr-review-cli.yml) v0.64.2, which spends fewer job-token API requests per run ([ci-workflows#869](https://github.com/melodic-software/ci-workflows/pull/869)). It reads the pull request's file list once instead of three times and pulls.get twice instead of three times, and the publish gate now comes through git. A whole review with an inline comment drops from 15 requests to 8. Check names, the marker comment, the review-complete notice and holds are unchanged.
