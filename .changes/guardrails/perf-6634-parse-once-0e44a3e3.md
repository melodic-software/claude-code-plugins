---
bump: patch
---

### Changed

- The shared `exec-bash.mjs` launcher has a `--bps-seed <hook-utils.sh>` flag. On Windows it parses a Bash or PowerShell call's command once with shfmt and jq, run only from absolute PATH entries and never from the working directory, and hands the result to the script, so Git Bash does not fork the processes of that parse. The flag is inert on other platforms, and an inherited result is always dropped (#6634).
