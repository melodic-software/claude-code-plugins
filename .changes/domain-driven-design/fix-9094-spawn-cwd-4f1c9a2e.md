---
bump: patch
---

### Security

- `glossary-settings.mjs` runs `git` from the plugin's own directory, so on Windows, where Node looks for a bare command in the working directory before `PATH`, a `git.exe` or `git.com` committed to the user's repository is never run.
