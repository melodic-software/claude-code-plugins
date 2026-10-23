---
bump: patch
---

### Fixed

- A read runner scan that refused or failed on a model call's output (an oversize patch, a leak-scan block, a refused decode) now hands the round to a person instead of ending it as `no-model-turn`. The new `scan-refusal` job in `pr-run-activity-read.yml` sets the `scan-refused` output from the scan job's result, so the value no longer depends on the failed scan job's own outputs. `address-feedback`'s reply job reads it as the new `review-scan-refused` input of `pr-run-activity-write.yml` and escalates `feedback-invalid`. `review-dependency`'s verdict job now receives the refusal it already acts on ([#9340](https://github.com/melodic-software/claude-code-plugins/issues/9340)).
- `address-feedback`'s reply job escalates `feedback-invalid` when the scan named replies it uploaded (a replies attempt or SHA-256) but none arrived, for example after a failed download, instead of skipping `no-model-turn` ([#9225](https://github.com/melodic-software/claude-code-plugins/issues/9225)).
- `pr-feedback-dispatch.yml` dispatches `address-feedback` again at a head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, on that head's next review or `pr-verify` completion. The `pr-unblock / address-feedback` check runs that started before that reply no longer hold the head. Each such round still posts its round marker, so the round cap bounds the retries ([#9218](https://github.com/melodic-software/claude-code-plugins/issues/9218)).
