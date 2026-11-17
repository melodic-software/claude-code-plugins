---
bump: patch
---

### Changed

- The pre-commit `lint` entry runs ShellCheck in parallel lanes, up to one per CPU and at most 8, with the scripts balanced across lanes by line count. A script over 2,000 lines is linted with `--extended-analysis=false`, the setting the ShellCheck manual recommends for scripts that size, when ShellCheck is 0.10 or later. Every other script keeps dataflow analysis. On a 44-file commit that touches 5,000- and 6,000-line scripts, the entry falls from 22.0 s to 3.0 s.
