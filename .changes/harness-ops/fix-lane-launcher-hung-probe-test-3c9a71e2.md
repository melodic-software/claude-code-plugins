---
bump: patch
---

### Fixed

- `lane-launcher.sh` takes `LANES_PLUGIN_TEST_TIMEOUT_S`, a bound for `claude plugin test` alone, so the hung-plugin-test case no longer races the `claude --version` probe on a slow runner. The production bound stays 20 s.
