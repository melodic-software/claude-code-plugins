---
bump: minor
---

### Added

- **Surviving mutants in `testing:test-value`.** A surviving mutant on changed code is named as one
  signal that a test checks too little, with `/mutation-testing:audit` as the way to get the
  survivors for a change.
- **Parallel isolation in `/testing:write`.** The determinism controls give each worker its own
  database or schema, bind test servers to port 0, give each test its own temp directory, and bar
  mutating a file or environment variable another worker reads. The agent finds its runner's
  worker id from the repository's test config and the runner's current docs at run time.
- Eval cases `tv-surviving-mutant-signal` and `wr-parallel-worker-isolation`.
