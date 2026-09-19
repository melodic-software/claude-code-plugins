# source-control configuration

Commit-subject / PR-title convention for the source-control plugin, resolved by
`/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
Re-run `/source-control:setup` to change these values.

Of the convention keys, `pr_body_required_sections` and `pr_skill_evidence` are set here. Every
other one falls through to `/source-control:setup`'s inference (this repo's commit history is
already Conventional-Commits-shaped) per config-resolution.md's per-key fallthrough, so this file
deliberately does not restate them. The `babysit_loop_*` keys below are the other key family this
file carries, and they are set explicitly.

`pr_skill_evidence` at the end of this file is this repository's mandatory map: which skills a pull
request owes evidence for, keyed on what its diff touches.
`plugins/source-control/scripts/skill-evidence.sh` is the one reader, and
`plugins/source-control/reference/config-resolution.md` owns the grammar. Two consequences of the
map below are worth stating plainly rather than leaving a reader to derive them.
`.github/claude-security-paths` lists `scripts/**`, `.claude/**`, every `plugins/*/skills/**` and
every `**/*.sh`, so the `security` class fires on nearly every non-docs pull request, which is the
breadth the local security review is meant to have. The `markdown` class matches `docs/topics/**`
too, so a docs-only pull request owes the two prose audits rather than being inert.

The `pr_body_required_sections` values below are the sections this repo's pull-request contract
actually asks for, each non-empty, alongside a native closing keyword. The contract runs in the
`ci-status` job of `.github/workflows/ci.yml`, in the `pr-contract` composite step pinned to
`melodic-software/ci-workflows/.github/actions/pr-contract`, which exempts `dependabot[bot]` from
the linkage check and no other author. The linkage half is advisory: a body that misses a closing
keyword or a required section gets a warning, an upserted comment and the `needs-issue-linkage`
label, and `ci-status` still passes on that account. The composite is the authority; this key
restates it so `/source-control:pull-request` drafts a body that conforms. Read the composite at the
SHA `ci.yml` pins, not at its default branch, since that pin is what actually runs. Re-read it
before changing either: an author or agent trusting a stale list writes a PR body that draws the
advisory label.

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

## pr_skill_evidence

- code | `**/*.sh **/*.bash **/*.py **/*.mjs **/*.js **/*.cjs **/*.ts **/*.ps1` | verification:confirm! review:quality-gate,review:fanout simplify
- markdown | `**/*.md` | ai-slop:audit docs-hygiene:audit-noise
- renames | `@renamed` | docs-hygiene:rename-references
- skills | `plugins/*/skills/** plugins/*/agents/**` | skill-quality:check
- rules | `.claude/rules/**` | instruction-placement:check
- security | `@file:.github/claude-security-paths` | review:security-review
