# source-control configuration

Commit-subject / PR-title convention for the source-control plugin, resolved by
`/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
Re-run `/source-control:setup` to change these values.

## subject_pattern

Conventional Commits

## type_list

build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test

## pr_title_pattern

Same as `subject_pattern`.

## pr_body_attribution

none
