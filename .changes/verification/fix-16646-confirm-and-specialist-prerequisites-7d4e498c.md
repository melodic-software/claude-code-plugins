---
bump: minor
---

### Changed

- `/verification:confirm` without the toolchain plugin now takes commands from the project's `.claude/ecosystems/` records first, runs a record's `requires` probes before a command, and reports an absent one as `skip (prerequisite missing: <name>)`, an environment skip that keeps the verdict below `CONFIRMED`. It never installs a declared prerequisite, and it installs lockfile dependencies only in an attended run; an unattended one reports `skip (dependencies missing: unattended run)`.
