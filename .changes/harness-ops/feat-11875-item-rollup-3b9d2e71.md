---
bump: minor
---

### Added

- `/harness-ops:observability items` rolls up usage per work item from the hot OTEL store: tokens by type and turns (`user_prompt` events), grouped by `autonomy.work_item.url` and `ccr_session_id`, with each item's cloud sessions listed. A row with no item URL joins its item through a `ccr.session.id` map built from the store's own pairs and an optional `--session-map` file; a cloud session tied to two items stays unattributed and is named. It reads no cost data, so no output carries a price ([#11875](https://github.com/melodic-software/claude-code-plugins/issues/11875)).
