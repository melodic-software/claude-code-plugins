---
bump: minor
---

### Changed

- `pr-merge.yml`: a run woken by `pull_request_target` skips its candidate listing and gate when a sweep that reached every candidate (no budget stop, a row per candidate in its `pr-merge-summary` artifact) finished within the new `merge.event-sweep-min-minutes` (default 10, `0` never skips), and logs `event-sweep-skip: last-sweep-finished=<iso> age-min=<n> min-minutes=<N>`. The post-merge check still runs, and scheduled and hand-started runs always sweep ([README.md, The pr-merge lane](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#the-pr-merge-lane)).
