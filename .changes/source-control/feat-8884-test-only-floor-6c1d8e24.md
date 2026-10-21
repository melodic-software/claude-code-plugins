---
bump: minor
---

### Added

- exempt test-only changes under floored script paths from the HIGH path floor

  `babysit_risk.score` no longer holds a file for the floor's
  `plugins/*/scripts/**`, `plugins/*/skills/*/scripts/**` and
  `plugins/**/scripts/**` entries or for `floor-script-scopes` (`high-script`,
  mode 100755 included) when every path of the file is a test: a
  `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name, or a `tests` or
  `fixtures` directory, matched case-sensitively. A file with an unsafe path,
  under a path a base-side declaration runs, or renamed from a non-test path
  still holds, and so does a configured copy of those globs. Every other floor
  entry, `denied-paths`, `floor-paths` and top-level scripts are unchanged, so
  a pull request mixing tests with any other floored file still holds.
