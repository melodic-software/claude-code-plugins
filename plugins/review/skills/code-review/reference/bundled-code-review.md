# The bundled `code-review` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The store row for this pair lives in the marketplace repository's native
surfaces registry; this file is what the model reads.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `code-review` ships with Claude Code as a bundled skill, alias `/review`, user-invocable, and Claude may start it on its own | The `/code-review` row on <https://code.claude.com/docs/en/commands> is labeled Skill with the `/review` alias; the installed 2.1.263 binary registers it with `aliases:["review"]` and `userInvocable`; "Let Claude start the review" on <https://code.claude.com/docs/en/code-review> states model invocation and the `skillOverrides` value (`user-invocable-only`) that stops it | 2026-09-11 | A release note names `/code-review` or bundled-skill invocability, or the row leaves the commands table |
| Bare `/code-review` reviews the branch's commits ahead of upstream plus uncommitted changes; a file path, PR number, branch, or ref range (`main...my-feature`) retargets it | "Review a diff locally" on the code-review page | 2026-09-11 | The page changes the target list |
| `--fix` edits the working tree (a background review's edits sit outside session checkpoints, so `/rewind` does not undo them); `--comment` posts inline comments on a GitHub PR or one note on a GitLab MR (needs `glab`, 2.1.257 or later); `ultra` launches the cloud review; a bare run reports into the session and writes nothing | Same page; the commands row lists the three flags | 2026-09-11 | A flag is added, removed, or changes what it mutates |
| It runs as a background subagent by default, foreground in `-p` runs; it follows `CLAUDE.md` and does not read `REVIEW.md` | Same page, "Run in the foreground" and "What the review reads and edits" | 2026-09-11 | Either section changes |
| The managed Code Review GitHub App is a third surface: research preview, Team and Enterprise plans, unavailable under Zero Data Retention, always a neutral check run | Note at the top of the code-review page and "Check run output" | 2026-09-11 | The page drops the preview label or changes the plan list |

## Why the verdict is complementary

This skill is the review logic the `claude-review` reusable workflow runs in CI: the wrapper
supplies the repository, PR number, and head SHA, installs the inline-comment server, and owns
posting; this skill owns what to look for and scopes security out where a security lane exists.
The bundled skill is a session-local review a developer runs before pushing, and its `--comment`
path posts as that developer. Neither replaces the other, and the managed service is a third
surface with its own trigger and billing. The three-surface breakdown lives in the `quality-gate`
skill's PR context ([../../quality-gate/context/pr.md](../../quality-gate/context/pr.md)); this
lane repeats only the part that changes what it does.

## Presence

The bundled skill is gated by `disableBundledSkills`, a `skillOverrides` entry, the host surface,
and the environment. Nothing in this lane depends on it: the CI wrapper never invokes it, and a
session where it does not resolve is an ordinary session.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which the
skill appears as a bundled skill with the `review` alias. This record re-verifies the same facts on
the installed 2.1.263 binary by string search (the registration carries `menuDescription:"Review
the current diff or a PR for bugs and cleanups"` and `subcommands:{ultra:"ultrareview"}`) and against
the two pages named above, all on 2026-09-11.
