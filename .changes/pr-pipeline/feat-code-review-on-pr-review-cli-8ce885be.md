---
bump: minor
---

### Changed

- The code review lane (`pr-review-hosted.yml`) runs on ci-workflows' [`pr-review-cli.yml`](https://github.com/melodic-software/ci-workflows/blob/83b739f625b501ad40c65dee7168d836883195e1/.github/workflows/pr-review-cli.yml) (v0.63.1), lane `code`: the reviews role's API key first, and its subscription token only after the key hands off or when the repository variable `REVIEWS_KEY_EXHAUSTED` is `true`. The check stays `pr-review / claude-review-status`; the review now posts as `github-actions[bot]`, each comment ending in its `claude-lane: claude-review` footer. A newer push no longer cancels a running review: it waits for it.
- Both review lanes now run on `pr-review-cli.yml`, funded by the `reviews` role's `REVIEWS_CLAUDE_API_KEY` and `REVIEWS_CLAUDE_CODE_OAUTH_TOKEN`; the code lane no longer reads the bare `CLAUDE_CODE_OAUTH_TOKEN`.
