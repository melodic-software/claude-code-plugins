---
bump: patch
---

### Fixed

- `pr-unblock-dispatch.yml` dispatches `review-dependency` again at a head whose newest `pr-unblock / apply-dependency-verdict` check skipped `no-model-turn`. The `pr-unblock / review-dependency` check runs that started before that verdict no longer hold the head, a limit stop aside. Each such round still posts its round marker, so the round cap bounds the retries. The dispatcher records a head as reviewed only once a verdict check started after its newest `review-dependency` check, so the record cannot hold a head that a later `no-model-turn` verdict releases ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362)).
