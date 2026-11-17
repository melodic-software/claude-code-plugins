---
bump: major
---

### Changed

- The pre-commit entry and the opt-in end-of-turn check run through the shared format and lint runner. They lint every GitHub Actions workflow file a change touches, applying the repository's own actionlint config (`.github/actionlint.yaml` or `.github/actionlint.yml` at its root) when there is one and actionlint's defaults otherwise. They never run a command from the repository's github-actions record (`.claude/ecosystems/github-actions.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists.
- `setup check` reports what lint resolves to from the entry's `--resolve` row: the adapter and the config it applies, or unresolved where the repository has no workflow files. File names reach actionlint as arguments, never as shell text.
- A partly staged workflow is linted from the index with `-stdin-filename`, so the config's `paths:` rules apply to it. actionlint exiting non-zero without a `<path>:<line>` finding, such as on a config it cannot parse, fails the commit and shows its output.

### Removed

- The `actionlint-check` git-hook entry is retired for `lint`. Installed copies, lefthook jobs and the `checks.actionlint.actionlint-check.declined` key change; `setup check` reports an installed `actionlint-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `actionlint-check` carries to `lint`.
