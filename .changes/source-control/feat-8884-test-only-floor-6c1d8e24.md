---
bump: minor
---

### Added

- exempt test-only changes under floored script paths from the HIGH path floor

  `babysit_risk.score` no longer holds a file for the floor's
  `plugins/*/scripts/**`, `plugins/*/skills/*/scripts/**` and
  `plugins/**/scripts/**` entries, for `floor-paths` globs whose last segment
  other than `**` is `scripts` (unless spelled like another fixed floor
  entry, which keeps holding), or for `floor-script-scopes` (`high-script`,
  mode 100755 included) when every path of the file is a test: a
  `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name, matched
  case-sensitively. A file only a `tests` or `fixtures` directory marks still
  holds, because an unchanged shipped file the scorer cannot read may source,
  glob or copy it. A file with an unsafe path, under a
  path a base-side declaration runs, renamed from a non-test path, or named by
  another changed file's patch or text (or beside a file with neither) still
  holds, and so does a `denied-paths` copy of those globs. Every other
  floor entry and `floor-paths` glob, and top-level scripts, are unchanged, so
  a pull request mixing tests with any other floored file still holds.
