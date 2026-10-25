---
bump: patch
---

### Fixed

- `plugins sync`: an `--only-install` re-entry keeps the first pass's state. The `install_new` policy and the invalid value it replaced are saved in the run's `flags.json` and read back, so the superseding digest and report still warn that the configured value is not `all`, `none`, or `ask`. The first pass's run timings are saved to `first-pass-run.json`, so the re-entry's run `timings` sum both passes, list each one under `timings.passes[]`, and the run `Timing:` row names both passes and says the wait between them is not counted.
