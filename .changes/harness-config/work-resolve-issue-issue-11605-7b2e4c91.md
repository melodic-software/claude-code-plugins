---
bump: patch
---

### Fixed

- `audit-permission-state` and `audit-permission-grants` still stop with exit 2 when `jq` is missing, and the message now says how to install it. It gives the install command for the platform (`brew install jq` on macOS, `winget install jqlang.jq` on Windows, and the `apt-get`, `dnf`, `zypper` or `pacman` command on Linux, depending on which one is on PATH). It also links the jq download page and points to `/harness-ops:prerequisites`. Before, a host with python3 and no jq, such as a stock WSL Ubuntu install, got only `ERROR: jq required` ([#11605](https://github.com/melodic-software/claude-code-plugins/issues/11605)).
