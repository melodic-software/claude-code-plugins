---
bump: minor
---

### Added

- `<home>/comment-policy.yaml` holds the comment policy: `comment_posture`, `comment_lint`,
  `comment_adr_dir`, `comment_lint_allow`, `comment_lint_exclude`, `comment_lint_keep_opening`,
  `comment_keep_list` and `class_c_max_lines`. `comment-policy.local.yaml` is its personal override
  for `comment_posture`, `comment_keep_list` and `class_c_max_lines`. Both are validated by the new
  `schemas/comment-policy.schema.json`; `code-tidying.yaml` keeps the remover and upkeep keys.
- `scripts/comment-settings.sh --files` prints the four settings file names in read order;
  `comment-lint-ci.sh` copies the merge base's files from that list.
- Retirement records `code-tidying-r001` and `code-tidying-r002`: `/code-tidying:setup check`
  reports a `code-tidying.yaml` or `code-tidying.local.yaml` that still sets a policy key, and
  `apply` moves the keys with the operator's confirmation.

### Deprecated

- Policy keys in `code-tidying.yaml` and `code-tidying.local.yaml`. A key a layer's comment-policy
  file does not set is still read from the same layer's code-tidying file, and every run names that
  file on stderr with the keys to move; the comment lint and `/code-tidying:remove-comments` show
  the line.
