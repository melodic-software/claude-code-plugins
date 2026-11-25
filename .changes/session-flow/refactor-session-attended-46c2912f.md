---
bump: minor
---

### Changed

- The observer catch-up hook arms from the shared attended predicate (`hooks/session-attended.sh`) instead of `CLAUDE_CODE_ENTRYPOINT == cli`: an attended session now arms whatever its entrypoint reads, unless that value is headless, and an unattended session whose entrypoint reads `cli` no longer does.
