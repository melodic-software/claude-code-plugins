---
bump: minor
---

### Added

- `/multi-agent:audit-defaults registry` proposes promoting a shipped `support-only` benchmark row to `permanent` once it has passed every check (page read live, dated within 6 months, an error range stated, current models tested from every vendor its work types need) in at least 3 audits spanning at least 30 days, listing the audit dates as evidence. The promotion ships only through the existing reviewed apply step.
- The registry judge returns a closed `error_range` field (`yes`, `no` or `unclear`).
- Each completed registry audit records its per-row check outcomes in this machine's plugin data directory (`registry-history/`) through `skills/audit-defaults/scripts/registry-history.mjs`, keeping only the records the promotion window needs plus a margin.
- New settings `vendors.promotion_audits` (default 3) and `vendors.promotion_days` (default 30), resolved through the usual config layers.
