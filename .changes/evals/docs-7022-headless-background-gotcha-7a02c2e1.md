---
bump: patch
---

### Fixed

- `plugin-eval`'s headless stay-attached step no longer says a `-p` session that backgrounds the
  CLI always ends the run. It keeps the foreground instruction, warns that a shell `&` gets no
  wait, says a command started with the Bash tool's `run_in_background` holds a `-p` run open
  until it exits or reaches its time limit, and points at the upstream sections on both. `records.md` now labels the old observations as seen on those versions and
  records the 2026-10-31 probe on 2.1.316
  ([#7022](https://github.com/melodic-software/claude-code-plugins/issues/7022)).
