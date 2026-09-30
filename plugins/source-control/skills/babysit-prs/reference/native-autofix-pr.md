# The built-in `/autofix-pr` command: verification record

Detail behind the `/autofix-pr` Boundary section in [SKILL.md](../SKILL.md). Each row is a four-part record: the claim, the basis it rests on, the date
it was checked, and the event that makes it worth checking again. "The extraction" below is the
`/claude-ops:inventory` extraction of the installed 2.1.284 binary, 2026-09-29.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `autofix-pr` is a built-in command described as "Monitor and autofix any issues with the current PR". User-invocable only (not model-invocable), hidden, gated | The extraction | 2026-09-29 | A release changes its invocability, visibility, or gate |
| `/autofix-pr [prompt]` spawns a cloud session that watches the current branch's PR and pushes fixes when CI fails or reviewers leave comments; it requires the `gh` CLI and access to cloud sessions | The `/autofix-pr` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | That row changes |

## Why the verdict is complementary

`/autofix-pr` covers one PR, the current branch's, from a cloud session that outlives the local
one and fixes everything by default. This skill covers the person's whole set of open PRs from the
local session, and every mutation passes a deterministic gate at the tier the person chose. The
model offers `/autofix-pr` to the person because only the person runs it.
