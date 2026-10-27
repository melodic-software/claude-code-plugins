---
bump: patch
---

### Fixed

- The fix-docs dispatcher no longer dispatches a head again on every cycle when its runs post no check, as a run whose run job emits an empty head does under `post-decline: false` ([#9247](https://github.com/melodic-software/claude-code-plugins/issues/9247)). The dispatch record keeps the fix-docs runs dispatched on each head; once `limits.limit-stops-per-head` of them are kept, the dispatcher reads each one's status and jobs through the Actions API, and a head with that many whose `fix-docs / broker-allowed` job succeeded gets one warning and is recorded as handled until a new push. Broker-refused, held and deleted runs do not count, and a head whose runs cannot be read is not dispatched (`.github/scripts/pr-unblock/fix-docs-dispatch.mjs`, `dispatch-record.mjs`).
