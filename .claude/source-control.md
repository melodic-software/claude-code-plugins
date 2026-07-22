# source-control configuration

Commit-subject / PR-title convention for the source-control plugin, resolved by
`/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
Re-run `/source-control:setup` to change these values.

Only `pr_body_required_sections` is set here — every other key falls through to
`/source-control:setup`'s inference (this repo's commit history is already Conventional-Commits-shaped)
per config-resolution.md's per-key fallthrough, so this file deliberately does not restate them.

## pr_body_required_sections

- Summary
- Test plan
- Related
