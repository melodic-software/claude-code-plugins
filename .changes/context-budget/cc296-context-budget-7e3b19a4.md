---
bump: minor
---

### Added

- **A lever for turning WebFetch off.** The audit's lever catalogue gains `disable-web-fetch` for `CLAUDE_CODE_DISABLE_WEB_FETCH=1` (Claude Code 2.1.285 or later), beside the Workflow and Artifact switches. A probe on Claude Code 2.1.296 showed the variable removes WebFetch from the tool list rather than refusing its calls. How much it saves depends on whether WebFetch is deferred in the session, so the audit prices it per bucket.

### Fixed

- **The `--bare` lever no longer understates what bare mode drops.** From Claude Code 2.1.286, `--bare` (and `CLAUDE_CODE_SIMPLE`) also connects only the MCP servers named on the command line, sends no system reminders and starts no background tasks. The `bare-simple-mode` lever now names those buckets, measures System prompt, System tools, MCP tools and Skills as well as Memory files, and records that the headless, CLI and env-var reference pages differ on what bare mode limits.
