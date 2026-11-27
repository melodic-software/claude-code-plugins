---
bump: patch
---

### Changed

- The `maintenance-scan-architecture` model legs set run-claude-cli's `block-outside-reads`, so Claude Code refuses their file-tool reads outside the checkout in every permission mode, and the gate step sets `READS_CONFINED=true`: the lane's runs no longer stop as `reads-unconfined`. A test fails the workflow if the gate claims confined reads while any leg leaves the block off. The lane stays `enabled: false`.
