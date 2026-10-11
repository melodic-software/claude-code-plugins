---
bump: minor
---

### Added

- **`developer`, `research` and `doctor` in `/firecrawl:firecrawl`.** The commands table and `context/commands.md` cover the coding-agent index search, the paper index and GitHub history search, and `doctor <job-id>` for a failed job, with flags read from `firecrawl-cli` 1.26.3 `--help`. A new gotcha says to run `doctor` before retrying a failed job with guessed flags.

### Changed

- **First recorded upstream sync.** `/firecrawl:update`'s `upstream.md` records the upstream `SKILL.md` hash from 2026-10-11 and CLI 1.26.3, so `--check` no longer reports upstream drift for it.

### Fixed

- **The `firecrawl init` warning matches what it does now.** It installs upstream's CLI and workflow skills globally for every detected agent and registers no MCP server, which the old text said it did.
