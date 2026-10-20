---
bump: patch
---

### Fixed

- A guard row launched through `exec-bash.mjs` now blocks (exit 2) when its bash child crashes or is killed, instead of exiting 1 and letting the tool call through. Every `run-guards.sh` row in `hooks.json` passes the new opt-in `--fail-closed` flag, so a non-zero exit other than 2 (such as 139 from a SIGSEGV), a signal death, or a spawn error denies the call with one stderr line naming the script and the cause. A missing bash still exits 1.
