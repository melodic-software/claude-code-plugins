---
bump: minor
---

### Changed

- `review-venue.sh` finds the code-review lane on ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/83b739f625b501ad40c65dee7168d836883195e1/.github/workflows/pr-review-cli.yml) from a caller whose path does not contain `security`; a caller whose path does still counts only for security-review.
