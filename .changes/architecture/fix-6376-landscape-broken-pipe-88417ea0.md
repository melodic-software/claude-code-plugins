---
bump: patch
---

### Fixed

- `landscape-record.sh --drift-against` no longer reports drift that is not there ([#6376](https://github.com/melodic-software/claude-code-plugins/issues/6376)).
  It checked each repository and edge key with `printf | grep -qxF` under `pipefail`. Bash writes that `printf` one line at a
  time, so when `grep -q` matched an early line and exited, the next write failed with a broken pipe, the pipeline failed, and
  a key present in both collections was reported as removed or added, exiting 3. The check now reads a here-string, which has
  no writer to race. This is also why `landscape-record.test.sh` failed intermittently; the timestamp fix in 0.22.0 for
  [#5785](https://github.com/melodic-software/claude-code-plugins/issues/5785) did not reach this cause.
