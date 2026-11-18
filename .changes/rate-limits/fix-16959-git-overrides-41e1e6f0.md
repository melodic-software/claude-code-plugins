---
bump: patch
---

### Security

- The shared hook::file_is_gitignored check runs git with core.fsmonitor and core.hooksPath turned off on the command line, through the new hook::git_untrusted helper, so a repository whose config names a command cannot make it run.
