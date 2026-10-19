---
bump: patch
---

### Changed

- `/discovery:research` now bounds the verify-and-rework loop at medium budget and above to one rework round: a verifier row still FAIL after the re-verify is recorded as a Gap or Conflicts entry (or the named `verification: fail rows` value) instead of reworked again. The skill also states who writes `RESEARCH.md`: the `discovery:researcher` subagent in the standard dispatch, this session from the sweep result in the deep tier's workflow path.
- Four new eval cases (45-48) grade the one-round cap, the fallback after a sweep artifact fails `check-source-applicability.py`, the researcher as the standard-dispatch `RESEARCH.md` writer, and the wide fan-out spawning the remaining researchers when usage has room.
