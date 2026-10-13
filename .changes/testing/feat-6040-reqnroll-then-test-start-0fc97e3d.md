---
bump: minor
---

### Added

- `/testing:audit` judges each Reqnroll `[Then]` step method in a C# step definitions file as a test, so a `[Then]` step with no assertion, or only `Assert.True(true)`, is reported. `[Given]` and `[When]` steps arrange and act, and are not judged ([#6040](https://github.com/melodic-software/claude-code-plugins/issues/6040)).
