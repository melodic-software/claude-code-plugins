---
bump: patch
---

### Changed

- **The guard-launch monitor's Stop row now runs only after a guard launch it has not checked.** Each guard launch removes the session's `.seen` file and writes a token unique to that launch (epoch seconds, bash PID and `$RANDOM`) into its `.launched` marker. After a run with nothing to report, the monitor copies each token at least 70 seconds old (the guard rows' 60-second hook timeout plus a margin) into `.seen`. While every `.launched` holds a token its `.seen` repeats, the Stop row skips and starts only node. An empty, unreadable or malformed `.launched`, or a missing or unreadable `.seen`, runs the monitor; a session with no `.launched` keeps the existing skip. Shared `exec-bash.mjs` synced.
- When a guard launch can neither remove `.seen` nor open `.launched`, the guard adds a `systemMessage` naming that marker to its output. Its decision and exit status do not change.
