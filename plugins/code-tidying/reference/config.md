# code-tidying: consumer configuration

The upkeep team layer is `<home>/code-tidying.yaml`, validated by
[`schemas/code-tidying.schema.json`](../schemas/code-tidying.schema.json). `<home>` is the convention
home the repository binds in its root instruction file, `docs/conventions` when it binds none or
declined one. `/code-tidying:tidy` works with zero config: every key it reads has a default. An
upkeep batch also needs `upkeep_spec_issue`, which has none.

| Key | Values | Default | Meaning |
|---|---|---|---|
| `upkeep_cadence` | `daily`, `weekly` | `daily` | How often an upkeep batch may open pull requests. |
| `upkeep_backstop` | `weekly`, `monthly` | `weekly` | An area changed since its last sweep is overdue once its oldest unswept commit is older than this window, and goes ahead of other changed areas. An unchanged area is never swept. |
| `upkeep_max_open` | integer, 1 or more | `3` | At most this many `chore/tidy-*` pull requests open at once: `/code-tidying:tidy` stops at it, and an upkeep batch opens only the difference. |
| `upkeep_spec_issue` | issue number | none | The issue holding the sweep's contract. Each upkeep batch pull request's body opens with `Refs: #<n>`, the spec a verifier judges it against; a batch with no valid value opens no pull request and fails, saying why. |
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` | How much independent checking `/code-tidying:batch-simplify` runs (Phase 6: the repo-mode refutation verifier, and under `strict` a verifier in the diff-scoped modes too), read by `lib/read-verification.sh` from the default branch's committed copy only, never `upkeep-setting.sh`; a skill entry beats the plugin value ([verification level](../../../docs/contracts/verification-level/README.md)). |

`skills/tidy/scripts/upkeep-setting.sh <key>` is the one reader. It prints the value and the layer
that supplied it. A value outside the table, or a file that does not parse, is reported with its file
and key, and the key resolves to its default. At a root that is `$HOME`, an ancestor of it, or not a
git working tree, or under a broken pointer, the team layer does not apply.

The surface has the plugin default and the team layer only: no `userConfig` option and no personal
override, because the limit protects a shared review queue.

## Which file holds which key

A key belongs to the comment policy when it decides which comments may exist: the comment lint reads
it, or it changes what the `necessary` posture keeps. A key that only tunes how
`/code-tidying:remove-comments` edits stays in `code-tidying.yaml`.

| Key | Team file | Personal override | Readers |
|---|---|---|---|
| `comment_posture` | `comment-policy.yaml` | `comment-policy.local.yaml` | comment lint, `/code-tidying:remove-comments`, `/code-tidying:tidy` |
| `comment_keep_list` | `comment-policy.yaml` | `comment-policy.local.yaml` | `/code-tidying:remove-comments` |
| `class_c_max_lines` | `comment-policy.yaml` | `comment-policy.local.yaml` | comment lint, `/code-tidying:remove-comments` |
| `comment_lint`, `comment_adr_dir`, `comment_lint_allow`, `comment_lint_exclude`, `comment_lint_keep_opening` | `comment-policy.yaml` | none: team file only | comment lint |
| `comment_edit_scope`, `encode_constraints_unattended`, `apply_local_renames` | `code-tidying.yaml` | `code-tidying.local.yaml` | `/code-tidying:remove-comments` |
| `upkeep_*`, `verification`, `verification_skills` | `code-tidying.yaml` | none | the readers in the table above |

Every file sits in `<home>`. `comment-policy.yaml` is validated by
[`schemas/comment-policy.schema.json`](../schemas/comment-policy.schema.json), which serves the
personal override too. `scripts/comment-settings.sh` is the one reader of the comment and remover
keys; its `--files` prints the four file names in read order, and no other script names them.

A layer whose comment-policy file does not set a policy key is read from the same layer's
code-tidying file for it. A comment-policy file that sets the key, with a valid value or not, wins,
so an invalid value there is dropped and never falls through to the code-tidying copy. A personal
value beats the team value whichever file supplies each. Every run names on stderr each
code-tidying file that still sets a policy key, with the keys to move, and names a team-only key
(`comment_lint`, `comment_adr_dir` or a lint list) in `code-tidying.local.yaml` as one to delete,
since no personal file supplies it; retirement records
`code-tidying-r001` and `code-tidying-r002` report the same keys in `/code-tidying:setup check`, and
`apply` moves them.

The hard-exclusion option and the focus area files are separate surfaces, described in the
[README](../README.md) and `skills/tidy/SKILL.md`.
