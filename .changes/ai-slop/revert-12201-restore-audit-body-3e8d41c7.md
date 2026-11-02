---
bump: patch
---

### Changed

- The `/ai-slop:audit` skill body is restored to its text before the trimmed version. A negative control showed the outcome suite cannot tell a loss in the body: a copy whose body was cut to one generic line scored 0.930 against the trimmed body's 0.950 on Opus 5.5 over the 9 loading cases, every pass VALID, so the earlier no-loss measurement could not vouch for the trim.
