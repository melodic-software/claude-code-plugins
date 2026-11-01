---
bump: patch
---

### Fixed

- The `verify-scripts` docs no longer say that code a read-runner script runs can read the job's GitHub token from an ancestor's `/proc/<pid>/environ`. The read runner's run-claude-cli steps set neither `GH_TOKEN` nor `GITHUB_TOKEN`, and the write runner's settings clear both ([#7919](https://github.com/melodic-software/claude-code-plugins/issues/7919)).
