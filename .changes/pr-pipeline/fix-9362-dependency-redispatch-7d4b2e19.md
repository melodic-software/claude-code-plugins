---
bump: patch
---

### Fixed

- `pr-unblock-dispatch.yml` dispatches `review-dependency` again at a head whose newest `pr-unblock / apply-dependency-verdict` check skipped `no-model-turn`. The `pr-unblock / review-dependency` check runs that started before that verdict no longer hold the head, a limit stop aside. Each such round still posts its round marker, so the round cap bounds the retries. The dispatcher records a head as reviewed only once a verdict check started after its newest `review-dependency` check, or once that check is a select job skip (`awaiting-human`, `not-applicable`, `superseded-sha`) that no verdict follows ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362)).
- The dispatch record's version is now 2, so `pr-unblock-dispatch.yml` and `pr-feedback-dispatch.yml` read a record cached under the old rule as empty. Such a record could still hold a `no-model-turn` head as handled and skip the release ([#9362](https://github.com/melodic-software/claude-code-plugins/issues/9362), [#9360](https://github.com/melodic-software/claude-code-plugins/pull/9360)).
