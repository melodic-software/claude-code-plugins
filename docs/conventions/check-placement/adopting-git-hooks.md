# Adopting the git-hook entries

How a repository takes on the git-hook entries the formatter, lint and guardrails plugins ship:
try one in a clone, clean up before a formatter goes live, share it with the team, or decline it.
Each plugin's setup installs its own entries with `apply install-git-hooks [scope=local|shared]`.
Where each check runs, and why, is in the [check-placement README](README.md).

## Try it in one clone

`scope=local` installs the entry in this clone only and commits nothing. Where it lands depends on
the hook manager the repository already uses:

| Manager | Local install |
|---|---|
| lefthook | a job in `lefthook-local.yml`, lefthook's per-clone config |
| husky | none: husky has no per-clone hooks, so setup offers `scope=shared` |
| plain git hooks | a dispatcher in the clone's hooks directory, or under `.githooks/local/` when the repository already uses plain shared hooks |

When nobody is there to answer the scope question, setup installs locally.

## Before enabling a formatter, a cleanup PR

The formatter entries (bash-format, biome-format, go-format, markdown-format, powershell-format,
ruff-format) rewrite each staged file in full. In a tree that was never formatted, the first commit
to touch a file also reformats the rest of it, and the real change is lost in the diff. Format
first:

1. Open one pull request per formatter holding only that formatter's output.
2. Once it merges, add the commit that landed on the default branch (with squash merge, the squash
   commit) to `.git-blame-ignore-revs` at the repository root, under a comment naming the
   formatter. GitHub's blame view skips the listed commits; local `git blame` skips them once a
   clone runs `git config blame.ignoreRevsFile .git-blame-ignore-revs`.
3. Then install the entry.

The other entries only report findings and change no files, so they need no cleanup PR.

Pointer: GitHub's
[Ignore commits in the blame view](https://docs.github.com/en/repositories/working-with-files/using-files/viewing-and-understanding-files#ignore-commits-in-the-blame-view),
and git's [`blame.ignoreRevsFile`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-blameignoreRevsFile).
As of 2026-10-17. Recheck when either section changes the file's name, location or format.

## Share it with the team

`scope=shared` writes and stages the entry under `.githooks/<plugin>/` together with the manager's
config (`lefthook.yml`, `.husky/<event>`, or `.githooks/` for plain hooks), for you to commit.
Review and merge those files like any change.

Committed config does not install itself: every clone runs the manager's install once.

- lefthook: `lefthook install`.
- husky: the project's package install, which runs husky's setup.
- plain git hooks: `git config core.hooksPath .githooks`.

A clone that skips this step gets no hooks, so for a team with authors outside Claude Code prefer
lefthook or husky over plain hooks. A clone that tried the entry locally moves to shared by
running setup with `scope=shared`; setup offers to remove the local copies once the shared entry
verifies. Committed hook config runs whatever the checked-out branch holds, so before committing
or pushing on a branch you do not trust, read its diff to `lefthook.yml`, `lefthook-local.yml`,
`.lefthook/`, `.lefthook-local/`, `.husky/` and `.githooks/`
([details](README.md#where-installed-copies-live)).

## Decline

A decline is a git config key, never committed. It silences the session-start drift line for that
entry; setup's `check` still reports it as `declined`.

| To decline | Run (setup's equivalent) |
|---|---|
| one entry in this clone | `git config --local checks.<plugin>.<entry>.declined true` (`decline --entry <entry>`) |
| one entry in every clone | the same key with `--global` (`decline --entry <entry> --global`) |
| every entry of every plugin | `git config --global checks.git-hooks.declined true` |

A clone opts one entry back in by setting its own key to `false`:
`git config --local checks.<plugin>.<entry>.declined false`. Installing the entry over a global
decline sets that for you.

## CI stays the enforcement point

A git hook runs on the author's machine, and anyone can get past it: `git commit --no-verify`
skips `pre-commit` and `commit-msg`, `git push --no-verify` skips `pre-push`, a clone may never
have installed the hooks, and `checks.skipmissing`
skips a check whose tool is missing. CI re-runs every check on the change whatever the hooks
reported, so a repository adopting an entry needs a CI job that runs the same tool. Setup says
when no CI workflow runs an entry's tool.

Pointer: git's [githooks `pre-commit`](https://git-scm.com/docs/githooks#_pre_commit) and
[`commit-msg`](https://git-scm.com/docs/githooks#_commit_msg) and
[`pre-push`](https://git-scm.com/docs/githooks#_pre_push) sections. As of 2026-10-17. Recheck
when any of them changes what `--no-verify` bypasses.
