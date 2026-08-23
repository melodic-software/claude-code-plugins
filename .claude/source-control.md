# source-control configuration

Commit-subject / PR-title convention for the source-control plugin, resolved by
`/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
Re-run `/source-control:setup` to change these values.

Of the convention keys, only `pr_body_required_sections` is set here — every other one falls through
to `/source-control:setup`'s inference (this repo's commit history is already
Conventional-Commits-shaped) per config-resolution.md's per-key fallthrough, so this file
deliberately does not restate them. The `babysit_loop_*` keys below are the other key family this
file carries, and they are set explicitly.

The `pr_body_required_sections` values below are the sections this repo's merge gate actually
requires, each non-empty, alongside a native closing keyword: `pr-issue-linkage`, defined in
`melodic-software/ci-workflows/.github/workflows/pr-issue-linkage.yml` and called by this repo's
`.github/workflows/pr-issue-linkage.yml` — which exempts `dependabot[bot]`, and no other author. The
gate is the authority; this key restates it so `/source-control:pull-request` drafts a body that
passes. Read the reusable at the SHA the caller pins, not at its default branch, since that pin is
what actually runs. Re-read it before changing either — an author or agent trusting a stale list
writes a PR body that fails CI.

## pr_body_required_sections

- Summary
- Fix
- Verification
- Related

## babysit_loop_stop_mode

standing

## babysit_loop_tier

worker

## babysit_loop_merge

c3-autonomous

## babysit_loop_grace_window_minutes

30
