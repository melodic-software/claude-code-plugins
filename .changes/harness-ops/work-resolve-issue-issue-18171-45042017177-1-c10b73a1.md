---
bump: patch
---

### Fixed

- `changelog apply --ci` no longer files a false `native-drift:inventory-broken` item each release when the runner has no native build. `native_drift.py diff --ci` then records "native drift not run in CI: no native build" in the report and files no inventory item. It also skips the `inventory-degraded` item a run with no previous summary would file only because the CLI moved past the validated build. A broken extraction of a native build still files ([#18171](https://github.com/melodic-software/claude-code-plugins/issues/18171)).
