---
bump: minor
---

### Added

- A `lint-full` pre-push entry runs ShellCheck with dataflow analysis on each pushed shell script over 2,000 lines, the scripts the pre-commit `lint` entry now checks without it, and blocks the push on a finding on a line the push adds. A script is read as the pushed tip holds it: in place when the work tree matches, else from a checkout of the tip. Installed hooks report the entry missing until `/bash-format:setup apply install-git-hooks` registers it.

### Changed

- The pre-commit `lint` entry runs ShellCheck in parallel lanes, up to one per CPU and at most 8, with the scripts balanced across lanes by line count. A script over 2,000 lines is linted with `--extended-analysis=false`, the setting the ShellCheck manual recommends for scripts that size, when ShellCheck is 0.10 or later; its dataflow checks (SC2218, SC2319, SC2320, SC2324) run at pre-push in `lint-full` instead. Every other script keeps dataflow analysis at commit. On a 44-file commit that touches 5,000- and 6,000-line scripts, the entry falls from 22.0 s to 3.0 s.
