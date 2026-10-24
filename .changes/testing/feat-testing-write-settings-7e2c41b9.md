---
bump: minor
---

### Added

- `/testing:write` reads two repository settings from `docs/conventions/testing.yaml` or
  `.claude/testing.local.yaml`, resolved by `scripts/resolve-config.sh write` and named with the
  layer that set each: `tdd_refactor_step` (`on | off`, default `on`) and `first_test`
  (`user-flow | unit`, default `user-flow`). The user-global file is not read for them and there is
  no `userConfig` option.
- With `tdd_refactor_step: on`, the skill closes each green with a line beginning
  `Refactor checkpoint:` that names what it tidied or why nothing needed it, and repeats those lines
  in its final summary, so a skipped Refactor step shows. The user-flow-first rule now follows
  `first_test`; with `unit` the user-flow test is still written before the task is done.
- Five eval cases cover each setting value and the default checkpoint report. `/testing:setup apply`
  keeps both keys, and the test scan skips them.
- A testing release without these keys stops its test scan on them in `testing.yaml`; add them once
  every member runs this release.
