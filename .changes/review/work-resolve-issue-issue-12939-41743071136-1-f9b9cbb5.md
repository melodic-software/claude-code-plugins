---
bump: minor
---

### Added

- `evals/revert-cases.sh` for a revert eval set on `/review:code-review` (#12939). `list` prints each revert pair in git history (original pull request, revert) and the pair count. `build` writes a `revert-<pr>-<slug>` case that grades whether the review posts a finding on a line the revert removed. `report` reads a run's `aggregate-result.json` and prints caught or missed per case and a total that is marked indicative below 5 cases. No CI job runs these cases.
