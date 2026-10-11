---
bump: patch
---

### Added

- **`browser-probe` eval case.** An environment probe for the browser eval lane, tagged `browser-probe` only so it runs alone under `--tag browser-probe`. Its deterministic graders record whether `playwright-cli` runs in the eval's Bash sandbox, Chromium launches (pinned by path, and the default channel), a workspace file page, a `127.0.0.1` page and a public page load, a screenshot is written, and whether the run can read a canary file inside the eval directory through `Read` or through the browser.
