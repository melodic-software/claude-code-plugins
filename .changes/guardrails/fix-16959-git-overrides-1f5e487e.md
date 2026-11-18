---
bump: patch
---

### Security

- The git ignore checks in secret-pattern-detection (`secret_pattern_detection_skip_gitignored`),
  hardcoded-path-check and the shared hook::file_is_gitignored run git with core.fsmonitor and
  core.hooksPath turned off on the command line, through the new hook::git_untrusted helper, so a
  repository whose config names a command cannot make it run.
