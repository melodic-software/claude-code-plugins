---
bump: minor
---

### Added

- `hooks/peer-list.mjs` builds the list of live Claude Code sessions on every fleet lane from `~/.config/fleet/fleet.json` (contract: `docs/contracts/fleet-manifest/`). It runs only each lane's `claude agents --json`, with no shell, an absolute program path and the home folder as working folder: over ssh with batch mode, strict host keys and no forwarding (the client option `ssh_client` names, else the platform's own; on WSL the Windows OpenSSH client), through WSL interop, or through `wsl.exe -d <distro> --exec` after checking the distro is running. A lane whose manifest entry falls outside the safe sets is never run and prints as `not reached (unsafe manifest entry)`. Every printed field from a peer is stripped of escapes and control characters and capped. With no fleet.json it lists only its own lane, through the binary `CLAUDE_CODE_EXECPATH` names, when that file is named `claude`, `claude.exe` or a version number.
- A SessionStart hook (`hooks/hooks.json`) adds that peer list to the context of every session on startup, resume, `/clear`, compaction and fork, and prints nothing when no peer is live and no lane is broken. A session that is not attended lists only its own lane.
- Option `ssh_client`: the ssh client the peer list runs to reach another machine, an absolute path to a file named `ssh` or `ssh.exe`; empty uses the platform's own client, on WSL the Windows OpenSSH client.
- Option `peer_query_timeout_seconds` (0 to 10, default 3): how long the peer list waits for each lane; 0 lists only the own lane.
- `peer-list.mjs --preview [--manifest <file>]` prints the list the hook would add, as text.
