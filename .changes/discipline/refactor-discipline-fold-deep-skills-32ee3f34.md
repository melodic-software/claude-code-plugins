---
bump: minor
---

### Removed

- **`/discipline:do-your-research-deep` and `/discipline:recheck-against-upstream-deep`.** Each fan-out now runs as a tier of its base skill: `/discipline:do-your-research tiered` or `full` (or a "fact-check everything" / "verify every claim" request), and `/discipline:recheck-against-upstream fan-out <scope>` (or a whole-subsystem recheck request). The `research_deep_verification` option keeps its name and now sets the depth of `do-your-research`'s fan-out tier. A `batch_exclude`, `batch_promote`, or `batch_demote` entry naming a removed skill now matches no corrector; remove it through the plugin configuration prompt.

### Changed

- **A batched run never takes a fan-out tier.** `do-your-research` and `recheck-against-upstream` run only their inline audit inside a `/discipline:sweep-all` audit fork or any other fork, and recommend a direct fan-out run in their ledger instead; the sweep-all fork brief says the same.
