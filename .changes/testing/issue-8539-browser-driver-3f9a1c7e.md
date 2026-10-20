---
bump: minor
---

### Added

- `browser_driver` setting for `/testing:run-e2e`: the command name of the one browser tool a `playwright` drive uses (default `playwright-cli`), resolved through the same cascade as `e2e_driver` by `resolve-config.sh e2e` and as a `userConfig` option. `scripts/check-browser-driver.sh` stops the run before any drive, naming the setting, the value and its source, when that command is not on PATH; no other browser tool is substituted.
