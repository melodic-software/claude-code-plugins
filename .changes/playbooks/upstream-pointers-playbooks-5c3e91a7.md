---
bump: patch
---

### Fixed

- `/playbooks:boris` no longer tells readers to use a `fork: true` skill key, a removed auto-mode launch flag, or a stale Remote Control plan list; each tip now carries an amendment pointing at the live docs section.
- `/playbooks:repo-sweep` no longer says settings and hook edits under `~/.claude` need a restart; the step report says which ones do, from the live settings page.

### Changed

- `/playbooks:boris` drops restated model specs, prices, setting counts, the recurring-task expiry and bare-mode defaults in favor of anchored pointer records, and fixes model-overview links that redirected off path.
- `/playbooks:repo-sweep` replaces its per-version changelog restatement and plugin-loading paraphrase with anchored pointer records.
- `/playbooks:fable-5`, `/playbooks:skill-authoring`, `/playbooks:update`, the prompt-caching reference and the model-adaptation chapters replace restated subagent-resume, cache, effort, fallback, thinking-block and plugin-update behavior with pointers, and anchor bare docs links.
