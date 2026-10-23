---
bump: patch
---

### Fixed

- A read runner scan that refused or failed on a model call's output (an oversize patch, a leak-scan block, a refused decode) now hands the round to a person instead of ending it as `no-model-turn`. When the scan job fails or is cancelled, the new `scan-refusal` job in `pr-run-activity-read.yml` uploads a `scan-refused-<lane>-<activity>-<attempt>` marker artifact. The write runner's reply and verdict jobs download it by name, so no decision depends on a failed job's outputs reaching a `workflow_call` caller. `address-feedback` escalates `feedback-invalid`, and `review-dependency` escalates `dependency-fix-not-landed` for an oversize patch or `dependency-invalid` otherwise. The read runner's `scan-refused` output and the write runner's `dependency-scan-refused` input are removed ([#9340](https://github.com/melodic-software/claude-code-plugins/issues/9340)).
- `address-feedback`'s reply job escalates `feedback-invalid` when the scan named replies it uploaded (a replies attempt or SHA-256) but none arrived, for example after a failed download, instead of skipping `no-model-turn` ([#9225](https://github.com/melodic-software/claude-code-plugins/issues/9225)).
- `pr-feedback-dispatch.yml` dispatches `address-feedback` again at a head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, on that head's next review or `pr-verify` completion. The `pr-unblock / address-feedback` check runs that started before that reply no longer hold the head. Each such round still posts its round marker, so the round cap bounds the retries ([#9218](https://github.com/melodic-software/claude-code-plugins/issues/9218)).
