---
bump: minor
---

### Removed

- `merge.read-token-floor` and the pr-merge gate's switch to the lane App token. The gate's review-evidence reads (timeline, comments, review-lane runs with their attempts, jobs and annotations) stay on `GITHUB_TOKEN` whatever its budget, since GitHub's [Terms of Service](https://docs.github.com/en/site-policy/github-terms/github-terms-of-service) section H bars sharing tokens to exceed its rate limits ([owner decision](https://github.com/melodic-software/claude-code-plugins/issues/9297#issuecomment-6368281689)). A read refused for a rate limit is made once and not retried: the candidate's lanes read `evidence-missing` and it holds until a later run reads again. **Breaking:** `merge.read-token-floor` is gone from the schema, so a `pr-pipeline.yaml` that still sets it fails validation; delete the key.
