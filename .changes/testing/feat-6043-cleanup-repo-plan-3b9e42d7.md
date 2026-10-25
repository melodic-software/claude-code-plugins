---
bump: minor
---

### Added

- `/testing:cleanup <repository root>` prints a plan instead of refusing: one batch per test project (a C# project's folder, else each test file's folder), ordered by finding count from one audit run. Each chosen batch then runs through the unchanged single-folder steps with its own diff and approval, the next one starting only after the previous is committed. A project of kind `live` or `operational` is marked and skipped; it runs only when you name it, and then only in cannot-fail-only mode, which runs no test. Outside C# every kind is `unknown`, so the plan asks which projects reach live or shared environments, and an unattended run starts no `unknown`-kind batch ([#6043](https://github.com/melodic-software/claude-code-plugins/issues/6043)).
