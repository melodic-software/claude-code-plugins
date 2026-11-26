---
bump: minor
---

### Added

- `hooks/peer-list.mjs` builds the list of live Claude Code sessions on every fleet lane from `~/.config/fleet/fleet.json` (contract: `docs/contracts/fleet-manifest/`). It runs only each lane's `claude agents --json`, with no shell, an absolute program path and the home folder as working folder: over ssh with batch mode, strict host keys and no forwarding, through WSL interop, or through `wsl.exe -d <distro> --exec` after checking the distro is running. A lane whose manifest entry falls outside the safe sets is never run and prints as `not reached (unsafe manifest entry)`. Every printed field from a peer is stripped of escapes and control characters and capped. With no fleet.json it lists only its own lane, through the binary `CLAUDE_CODE_EXECPATH` names, when that file is named `claude`, `claude.exe` or a version number.
