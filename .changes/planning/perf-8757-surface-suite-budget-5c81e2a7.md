---
bump: minor
---

### Added

- **interview:** a `readingWindow` setting (default 180, 5 to 600 seconds) sets how long after an event is delivered the 1:1 interview page shows Claude working once no watcher waits. Before, the window was a fixed 180 seconds. The Settings panel shows it as a read-only row ([#8757](https://github.com/melodic-software/claude-code-plugins/issues/8757)).

### Changed

- The interview surface's browser suites are shorter. The journey's data dir sets `readingWindow` to 5, so phase 7 no longer waits out the 180-second window before it checks the Idle pill. `ui_page` moved into its own suite, `surface-page.test.sh`. The `ui_c` phases now run as three suites: `surface-ui-c.test.sh` (phases 1 to 3), `surface-ui-c-listen.test.sh` (4 to 6) and `surface-ui-c-ledger.test.sh` (7 to 10). Every check still runs ([#8757](https://github.com/melodic-software/claude-code-plugins/issues/8757)).
