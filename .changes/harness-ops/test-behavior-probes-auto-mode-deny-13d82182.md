---
bump: patch
---

### Added

- `behavior-probes`: five new auto-mode cases (a Write in the project, in an `additionalDirectories`
  entry and outside both; a `permissions.deny` rule against an `autoMode.allow` entry) and a new
  `deny-rules` area (a `Read(./.env)` deny against the Read tool, `cat .env` and `bash -c "cat .env"`;
  a `git reset --hard` deny against `git -C . reset --hard`; a `!` carve-out listed after and before
  the rule it carves from). Each case cites the docs section behind its expected outcome in a new
  optional `docs` field; the cases are listed as pending in `records.md` until their first live run.
