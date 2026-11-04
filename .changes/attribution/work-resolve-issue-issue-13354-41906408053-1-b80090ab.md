---
bump: minor
---

### Changed

- `/attribution:audit`: `excluded_paths` has a bundled default that declines test-fixture trees
  (`**/fixtures/**`, `**/__fixtures__/**`, `**/testdata/**`), so a repository that sets no value
  no longer audits planted fixture text as prose
  ([#13354](https://github.com/melodic-software/claude-code-plugins/issues/13354)).
  `list-corpus.sh` matches the default below the scan target and never applies it to a named file,
  so a run aimed at a fixture tree, a file target or a `--paths-file` entry still reads it, and any
  layer that sets `excluded_paths` (`[]` included) replaces it. The decline reason reads
  `excluded_paths (bundled default: test-fixture tree)`. `reference/rubric.md`,
  `skills/setup/reference/keys.md` and the schema describe the default.
- `fingerprint.mjs`: a URL counts as no words. `tokenize` used to split a URL into its scheme, host
  labels and path segments, so a cited link counted toward span word totals and a citation shared
  with its source matched as a copied span.

### Fixed

- `fetch-docs.sh --profile generic`: a `text/plain` answer to a URL whose path ends in `.md` is
  read as markdown on the first request, so a host that serves `.md` files as `text/plain` no
  longer leaves the page unread `unexpected-content-type`. A `text/plain` answer for any other
  path is still refused.
