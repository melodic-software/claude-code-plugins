---
bump: minor
---

### Changed

- The security review lane (`pr-review-security-hosted.yml`) runs on ci-workflows' `pr-review-cli.yml` (v0.63.0), lane `security`: the reviews role's API key first, and its subscription token only after the key hands off or when the repository variable `REVIEWS_KEY_EXHAUSTED` is `true`. The check stays `pr-review-security / security-review`; the review now posts as `github-actions[bot]`, each comment ending in its `claude-lane: claude-security-review` footer. A newer push no longer cancels a running review: it waits for it.
- `address-feedback` and `pr-feedback-dispatch.yml` treat a `github-actions[bot]` comment as the reviewer's when its last non-blank line is a review lane's footer and its review is `github-actions[bot]`'s; `claude[bot]` findings are unchanged.
- One funding role, `reviews`, backs both review lanes and is keyed; the `reviews-security` role is gone.
