---
bump: minor
---

### Added

- `.github/scripts/apply-patch/apply-patch.mjs`, the one script that applies a read model job's
  patch to a pull request branch, driven by the
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  row of the producer's prepare mode (`default` when it has none), read from the trusted base
  checkout. It refuses the whole patch on any change under `.github/` (any case, any `..` segment)
  or `.claude/`, to the root `.mcp.json`, `.gitmodules` or a `settings*.json`, on a symbolic link,
  gitlink or new executable bit, on a rename into any of those, on a path holding a backslash, on more paths than the row's
  `max-files`, on a path its allow predicates refuse, and on an Anthropic API key, OAuth token or
  GitHub token shape in the patch or a patched blob. A row without the universal refusals, or with
  an unknown predicate, throws before any write. A head that moved since the model job takes the
  patch with `git apply --3way` only when the moved commits touch no patched path, else it skips
  `superseded-sha`. The commit goes through the Git Data API with one blob per changed file plus a
  tree, a commit and a ref update. No workflow runs it yet
  ([README](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md#patch-rules)).
