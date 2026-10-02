# Changelog for on-demand dependencies

Notable changes to the on-demand dependency contract. The contract is versioned by the `Version:`
stamp in `README.md` (SemVer). A `[SPEC]` rule that tightens is a major bump; a new rule, exception
or adopter is a minor bump; wording is a patch.

## [1.0.0] - 2026-10-02

Initial published contract, written with the harness-ops inventory parser
([#5640](https://github.com/melodic-software/claude-code-plugins/issues/5640) P1), its first adopter.

- **Rule 1 [SPEC]**: commit `package.json` and `package-lock.json`, never `node_modules` or a bundle
  of third-party code; each lockfile directory has a Dependabot entry.
- **Rule 2 [SPEC]**: install on first use with `npm ci --ignore-scripts` into
  `<plugin data dir>/<component>/<lockfile hash>/`, atomically, with readiness decided by a load
  probe rather than a version floor, and the install base resolved in a stated order because the
  Bash tool does not receive `CLAUDE_PLUGIN_DATA`.
- **Rule 3 [SPEC]**: any failure reports the component broken with one repair command; no silent
  fallback.
- **Rule 4 [SPEC]**: no new committed third-party bundle. The miro MCP server bundle is the one
  known exception, tracked by
  [#5752](https://github.com/melodic-software/claude-code-plugins/issues/5752).
