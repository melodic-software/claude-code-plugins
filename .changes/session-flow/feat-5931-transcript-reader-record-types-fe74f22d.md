---
bump: minor
---

### Added

- `/session-flow:audit-sessions` knows the eleven record types current Claude Code versions write, so drift runs stop reporting them as `unknown-record-type`. `ai-title` feeds a new `link_keys.ai_title` (the generated session title, redacted and governed by `audit_sessions_excerpt_chars` like the custom title); `atis-latch`, `mode`, `bridge-session`, `relocated`, `file-history-delta`, `cost-state`, `fork-context-ref`, `frame-link`, `artifact-comment-monitor` and `artifact-autoreact-ledger` are recognized and skipped, so they feed no metric.
