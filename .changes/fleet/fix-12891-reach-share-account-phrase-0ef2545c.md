---
bump: patch
---

### Fixed

- reword reach's shared-account trigger so the other reach cases keep firing

  The trigger 'share one account across lanes' replaces 'one account for every lane'. On Sonnet it fires on the shared-account prompt as often as the old phrase, without the misses the old phrase showed on the same-repo and port-22 prompts.
