---
bump: minor
---

### Changed

- `/bugs:scan` no longer lets its hunters or verification gates run the scanned repository's code, since the checkout may be one nobody here controls. A gate names a cheap check in `proposed-check:` instead. A run passed the new `--unattended` flag runs no proposed check and labels every surviving finding `verified-by-reading`. An attended run asks the person before each proposed check, showing its exact command, and runs only the checks they approve; a finding is `reproduced` only when an approved check shows the predicted failure ([#7787](https://github.com/melodic-software/claude-code-plugins/issues/7787)).
