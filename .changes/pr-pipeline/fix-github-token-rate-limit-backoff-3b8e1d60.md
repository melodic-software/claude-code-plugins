---
bump: patch
---

### Fixed

- The pr-unblock and feedback dispatchers wait out a rate limit on the repository's job token instead of failing at once: retry-after when GitHub sends it, else until one second past the reset when no requests remain, else one minute, then the call is sent once more. Waits are capped at six minutes per run, summed; a reset further away fails at once and names the reset time.
