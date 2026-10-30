---
bump: patch
---

### Changed

- **Stryker.NET exercised-scope filter limits stated** ([#9687](https://github.com/melodic-software/claude-code-plugins/issues/9687)). `audit/context/tool-test-restriction.md` now says the joined `test-case-filter` can match more tests than the set: a generic class's term has no trailing `.`, and a term can match in another listed project. Those extra tests can turn NoCoverage into Survived or Killed. It also stops claiming the probe measured which directory `test-projects` paths resolve against.
