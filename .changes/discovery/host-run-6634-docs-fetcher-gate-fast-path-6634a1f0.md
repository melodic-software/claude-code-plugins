---
bump: patch
---

### Changed

- the docs-fetcher gate loads less on every main-thread Bash call

  The `PreToolUse` `Bash` gate now loads `node:fs` and `node:crypto` only when it records the docs-fetcher agent's one allowed call. Every other Bash call, in the main thread and in other agents, skips them. On a WSL2 host this cut the gate's main-thread time from about 7.5 ms above a bare `node -e 0` to about 4 ms (3 rounds of 30 interleaved runs). What the gate allows and denies is unchanged.
