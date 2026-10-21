# The bundled `code-review` skill: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again. The store row for this pair lives in the marketplace repository's native
surfaces registry; this file is what the model reads.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `code-review` ships with Claude Code as a bundled skill that Claude may also start on its own, so this lane never assumes a session-local review did or did not run | The installed 2.1.263 binary registers it with `aliases:["review"]` and `userInvocable` (2026-09-11). Pointer: its alias and label are read from the `/code-review` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands); model invocation and the setting that stops it from [code-review: let Claude start the review](https://code.claude.com/docs/en/code-review-local#let-claude-start-the-review) | 2026-10-11 | A release note names `/code-review` or bundled-skill invocability, or either section changes |
| Its default target and the ways to retarget it are the developer's choice and not this lane's; read them live when routing someone to it | Pointer: [code-review: review a diff locally](https://code.claude.com/docs/en/code-review#review-a-diff-locally) | 2026-10-11 | That section changes the target list |
| Only a run that reports into the session and writes nothing is read-only; any argument that edits the working tree or posts to a pull request or merge request makes it a mutating surface. Which arguments do which, and their version floors, are read live, never listed here | Pointer: [code-review: review a diff locally](https://code.claude.com/docs/en/code-review#review-a-diff-locally) and [code-review: what the review reads and edits](https://code.claude.com/docs/en/code-review-local#what-the-review-reads-and-edits) | 2026-10-11 | Either section adds, removes, or changes what an argument mutates |
| Its run mode and which instruction files it follows differ from this lane's; read them live before comparing the two | Pointer: [code-review: run in the foreground](https://code.claude.com/docs/en/code-review-local#run-in-the-foreground) and [code-review: what the review reads and edits](https://code.claude.com/docs/en/code-review-local#what-the-review-reads-and-edits) | 2026-10-11 | Either section changes |
| The managed Code Review GitHub App is a third surface; its availability and check-run behavior are recorded once, in the `quality-gate` skill's PR context | Pointer: [../../quality-gate/context/pr.md](../../quality-gate/context/pr.md#boundary-three-overlapping-review-surfaces), which holds the live pointer record | 2026-10-11 | That section moves, is renamed, or stops holding the App's pointer record |

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

Whether the bundled skill resolves depends on settings, the host surface, and the environment.
Nothing in this lane depends on it: the CI wrapper never invokes it, and a session where it does
not resolve is an ordinary session. Pointer: the settings that turn a bundled skill off or hide it
are read at [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings).
As of: 2026-10-11. Recheck trigger: that section adds or renames a setting.

## Extraction record

The registry row's observation is a 2026-08-23 extraction of the 2.1.232 binary, in which the
skill appears as a bundled skill with the `review` alias. This record re-verifies the same facts on
the installed 2.1.263 binary by string search (the registration carries `menuDescription:"Review
the current diff or a PR for bugs and cleanups"` and `subcommands:{ultra:"ultrareview"}`) and against
the two pages named above, all on 2026-09-11.
