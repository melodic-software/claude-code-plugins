---
bump: minor
---

### Changed

- A role chain's standing-rules file now lives at `handoffs/standing-rules/<chain-root-stem>.md`,
  outside `archive/`, since every hop rewrites it. Hops that name the old
  `archive/<chain-root-stem>/standing-rules.md` still validate, read and amend it there, and the
  chain's next hop writes the new path.
