---
bump: patch
---

### Fixed

- `plugin-eval`'s validity gate checks a plugin inside a case's directory (a case's own helper,
  such as an offline `gh` stand-in) only in that case's runs, so a mixed suite where one case has
  a helper and another has none no longer fails `plugins loaded` for the second.
- A denied compound Bash command now counts as a plugin-data denial when one of its commands is
  aimed only under the run's own plugin-data directory and every other absolute path it names was
  named by an allowed Bash call of the same run.
