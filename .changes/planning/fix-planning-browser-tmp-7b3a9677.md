---
bump: none
---

Test-only: the browser suites keep their browser temp folders inside folders they remove on exit. `surface-checks.sh` runs `playwright-cli` with `TMPDIR` under its scratch dir, so Chromium's `org.chromium.Chromium.*` folder and playwright-cli's `pw-*` socket folder go with it, and `ui.test.sh` exports `TMPDIR` under its output dir, so WebKit's profile and Playwright's artifacts folder do too; nothing a user runs changes.
