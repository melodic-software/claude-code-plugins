---
bump: minor
---

### Added

- exempt test-only changes under floored script paths from the HIGH path floor

  `babysit_risk.score` no longer holds a file for the floor's
  `plugins/*/scripts/**`, `plugins/*/skills/*/scripts/**` and
  `plugins/**/scripts/**` entries, for `floor-paths` globs whose last segment
  other than `**` is `scripts`, or for `floor-script-scopes` (`high-script`,
  mode 100755 included) when every path of the file is a test: a
  `*.test.mjs`, `*.test.sh`, `*.test.js` or `test_*.py` name, or a `tests` or
  `fixtures` directory below the path's last `scripts` directory and below its
  script scope, matched case-sensitively. A file with an unsafe path, under a
  path a base-side declaration runs, renamed from a non-test path, or named by
  another changed file's patch or text (or beside a file with neither) still
  holds, and so does a `denied-paths` copy of those globs. Every other
  floor entry and `floor-paths` glob, and top-level scripts, are unchanged, so
  a pull request mixing tests with any other floored file still holds.
