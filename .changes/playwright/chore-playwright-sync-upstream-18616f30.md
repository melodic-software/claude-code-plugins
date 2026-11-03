---
bump: patch
---

### Changed

- `/playwright:playwright` is synced to `@playwright/cli` 0.1.23. The command references now cover `tab-new --isolated-context`, `cookie-delete --domain` and `--path`, `console --all`, `requests --all`, `find --max-results`, negative `mousewheel` values and the `redactUrlParams` config setting. The tracing example opens the browser first, and the `--raw` guidance now says to pipe only from commands that return a value.

### Fixed

- The command reference and the orchestrator recipe named `playwright-cli network`, which the CLI rejects as an unknown command. They now use `requests`.
