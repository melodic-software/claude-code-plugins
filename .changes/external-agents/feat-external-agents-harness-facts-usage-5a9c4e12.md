---
bump: minor
---

### Added

- `external-agents models <product>` now includes product-level `tools`, headless `image` capability, optional per-model `context_window` when the CLI reports it, and live `breaker` state (`open`, `reason`, `reset_at`) while keeping schema version 1.
- `external-agents usage <product>` reads current plan usage remaining as a normalized 0 to 1 fraction in a single JSON object outside delegated runs, driven by each provider record (`codex app-server` `account/rateLimits/read` for Codex; `agy --output-format json -p=/usage` without `--disable-slash-commands` for Antigravity) without printing account ids, emails or plan names.
