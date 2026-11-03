---
bump: minor
---

### Added

- `pre-commit-content` and `pre-push-content` skip each path listed in the repository's
  `docs/conventions/guardrails-content-exempt.tsv` (`path<TAB>reason` rows; a directory ends in
  `/`), read from the default branch (`origin/HEAD`) so a change cannot exempt its own lines.
- `skill-reference-verify` treats a repository whose plugins carry a `.codex-plugin/` or
  `.cursor-plugin/` manifest as a marketplace, so its skill references are checked too.

### Changed

- `reference-verify`: a stale-path finding is printed and the push goes ahead, since a citation can
  be correct as written (a deletion record). A cli-flag or skill-reference finding still fails it.

### Fixed

- `reference-verify` reports a file whose verifier input it could not build, and a pushed tip it
  could not check out, as a finding that fails the push, instead of skipping it with exit 0.
