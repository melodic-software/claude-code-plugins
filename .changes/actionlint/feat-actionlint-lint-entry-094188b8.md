---
bump: major
---

### Changed

- The pre-commit entry and the opt-in end-of-turn check run actionlint only where the repository commits its own actionlint config, `.github/actionlint.yaml` or `.github/actionlint.yml` at its root. A repository without one is no longer linted by the hooks: add the config to opt in. They never run a command from the repository's github-actions record (`.claude/ecosystems/github-actions.yaml`); `/toolchain:lint` and `/toolchain:check` run it on request, and `setup check` says when a record exists.
- `setup check` reports what lint resolves to from the entry's `--resolve` row: the adapter and the config that opted in, or unresolved where no config is present. File names reach actionlint as arguments, never as shell text.
- A partly staged workflow is linted from the index with `-stdin-filename`, so the config's `paths:` rules apply to it. actionlint exiting non-zero without a `<path>:<line>` finding, such as on a config it cannot parse, fails the commit and shows its output.

### Removed

- The `actionlint-check` git-hook entry is retired for `lint`. Installed copies, lefthook jobs and the `checks.actionlint.actionlint-check.declined` key change; `setup check` reports an installed `actionlint-check` copy as superseded, `apply install-git-hooks` retires it, and a decline of `actionlint-check` carries to `lint`.
