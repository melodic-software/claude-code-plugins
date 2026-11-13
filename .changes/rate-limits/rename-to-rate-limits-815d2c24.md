---
bump: major
---

### Changed

- **Renamed to `rate-limits`.** The install id is `rate-limits@melodic-software`, the commands are `/rate-limits` and `/rate-limits:setup`, the options `rate_limits_enabled`, `rate_limits_band` and `rate_limits_toast` (their variables `CLAUDE_PLUGIN_OPTION_RATE_LIMITS_*`), the runtime directory `~/.claude/rate-limits/` and the status tool `mcp__rate-limits__status`. The other options keep their names. Saved option values carry over under the new keys where dotfiles manages the settings; elsewhere set them again with `/plugin configure rate-limits@<marketplace>`.
- `/rate-limits:setup check` reports a directory left by the plugin's earlier name as drift, and the new `/rate-limits:setup apply` moves its `stop-events.jsonl` into `~/.claude/rate-limits/` (appending to one already there) and removes it.
- Corrected in place: the title and the released entries [3.0.16], [3.0.0], [2.1.10], [2.1.9], [2.1.8], [2.0.10], [2.0.2], [0.17.0], [0.16.0], [0.15.0], [0.13.0], [0.12.0], [0.11.0], [0.10.4], [0.10.0], [0.8.37], [0.8.30], [0.8.24], [0.8.22], [0.8.17], [0.8.16], [0.8.14], [0.7.18], [0.7.0], [0.5.7], [0.5.6], [0.5.5], [0.4.3], [0.3.0], [0.2.1], [0.1.0] now name the plugin `rate-limits`; entries that named a skill, command or path removed before the rename describe it instead.
