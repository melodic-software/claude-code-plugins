# Changelog for on-demand dependencies

Notable changes to the on-demand dependency contract. The contract is versioned by the `Version:`
stamp in `README.md` (SemVer). A `[SPEC]` rule that tightens is a major bump; a new rule, exception
or adopter is a minor bump; wording is a patch.

## [2.3.0] - 2026-10-04

- **Rule P4**: in an interactive session the agent offers to run the repair line and runs it on the
  user's yes, per the prerequisites convention's
  [When a check fails](../prerequisites/README.md#when-a-check-fails-offer-the-fix-run-it-on-a-yes).

## [2.2.0] - 2026-10-02

- **Exceptions**: `explainer-video` installs `srt`, and on some platforms `pycairo` and `manimpango`,
  from hash-pinned source archives because no wheel exists for those platforms; every other package
  stays wheels only. The build backends are the one fetch pip does not hash-check
  ([#5861](https://github.com/melodic-software/claude-code-plugins/issues/5861)).
- **Adoption**: `explainer-video` is the second Python adopter.
- **Adoption**: the `speech` plugin's numpy and onnxruntime follow the Python rules
  ([#5859](https://github.com/melodic-software/claude-code-plugins/issues/5859)).

## [2.1.0] - 2026-10-02

- **Python section, Rules P1-P4 [SPEC]**: commit `requirements.in` and a universal, hash-locked
  `requirements.txt` (wheels only); a `SessionStart` hook installs it with
  `pip install --require-hashes --only-binary :all: --no-deps --target` into
  `<plugin data dir>/python/<lock hash>-<interpreter tag>/`, atomically and behind a load probe;
  nothing else fetches a package; every failure is a notice with one repair line.
- **Adoption**: the `animation` plugin's numpy and opencv are the first Python adopter
  ([#5844](https://github.com/melodic-software/claude-code-plugins/issues/5844)).

## [2.0.0] - 2026-10-02

- **Rule 3 [SPEC]** tightens: on Windows the repair line is Windows PowerShell 5.1 (no `&&`, single
  quotes doubled) and names `npm.cmd`, since the default execution policy blocks `npm.ps1`. The
  POSIX line is unchanged elsewhere. harness-ops adopts it
  ([#5826](https://github.com/melodic-software/claude-code-plugins/issues/5826)); miro prints
  `npm` on Windows until
  [#5880](https://github.com/melodic-software/claude-code-plugins/issues/5880).

## [1.0.1] - 2026-10-02

- **Exceptions**: the miro MCP server bundle is removed from the table, which is now empty. miro
  installs its dependencies on first launch under rules 1-3
  ([#5752](https://github.com/melodic-software/claude-code-plugins/issues/5752)).

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
