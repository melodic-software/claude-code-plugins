# source-control configuration

Tracked commit-subject / PR-title convention for the source-control plugin. `/source-control:commit`
and `/source-control:pull-request` resolve this file first, before inferring from the repo's own
CLAUDE.md/rules/commit-msg hook or falling back to the bundled Conventional Commits default.
Re-run `/source-control:setup` to change these values.

## subject_pattern

Conventional Commits

## type_list

build, chore, ci, docs, feat, fix, perf, refactor, revert, style, test

## pr_title_pattern

Same as `subject_pattern`.

## trailer_policy

Co-Authored-By: Claude <model> (<context>) <noreply@anthropic.com>
