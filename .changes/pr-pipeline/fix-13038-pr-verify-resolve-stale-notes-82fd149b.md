---
bump: patch
---

### Fixed

- A pr-verify pass that lands while an address-feedback round for the same lanes App PR is still queued or running now still sends its pass-only round, so the fail-note threads from earlier heads get resolved ([#13038](https://github.com/melodic-software/claude-code-plugins/issues/13038)). Before, `feedback-dispatch.mjs` skipped the dispatch as "not done yet", and nothing sent the pass again, so the threads blocked the merge until a person resolved them. The pass-only round now waits in `pr-unblock.yml`'s per-PR concurrency group behind that round. If that round moves the head, the pass-only round resolves nothing. A review run's round still skips while another round is going.
