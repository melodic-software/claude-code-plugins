---
bump: patch
---

### Fixed

- The video-digest readiness report runs when the `asr_python` option is unset. The pre-computed
  preflight command now single-quotes its `--asr-python` argument, so the literal
  `${user_config.asr_python}` token Claude Code leaves for an unset option reaches the script
  instead of failing in bash with "bad substitution".
