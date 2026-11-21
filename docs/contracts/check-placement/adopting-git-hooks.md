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

The formatter entries (bash-format, go-format, javascript-format, markdown-format, powershell-format,
python-format) rewrite each staged file in full. In a tree that was never formatted, the first commit
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
- Husky.Net: `dotnet tool restore`, then `dotnet husky install`.
- plain git hooks: `git config core.hooksPath .githooks`.

A clone that skips this step gets no hooks, so for a team with authors outside Claude Code prefer
lefthook or husky over plain hooks. A clone that tried the entry locally moves to shared by
running setup with `scope=shared`; setup offers to remove the local copies once the shared entry
verifies. Committed hook config runs whatever the checked-out branch holds, so before committing
or pushing on a branch you do not trust, read its diff to `lefthook.yml`, `lefthook-local.yml`,
`.lefthook/`, `.lefthook-local/`, `.husky/` and `.githooks/`
([details](README.md#where-installed-copies-live)).

## Share it through the lefthook remote

With lefthook, `scope=shared` prefers the remote: setup's `plan --scope remote` returns one
`remotes:` entry for the committed `lefthook.yml`, naming this repository's root
[`lefthook-remote.yml`](../../../lefthook-remote.yml). That file extends every plugin's
`git-hooks/lefthook-remote.yml`, so one entry carries every plugin's hooks, a plugin that adds a
remote config later reaches the repository with no change there, and nothing is copied or
refreshed in it. Each clone still runs `lefthook install` once. A repository whose entry lists
per-plugin configs replaces them with the root file.

Because the root file turns on every plugin's jobs, whichever plugin's setup runs the plan, the
plan's `aggregate.plugins` lists the plugins it enables, and its `missing-tool`, `declined` and
`migrate` decisions cover all of their entries, each naming its `plugin` when it is not the
plugin running the plan. `verify` adds a `tool\t<tool>\tmissing\t<plugin>-<entry>` line for each
of their entries whose tool is absent. Both read the plugins from the fetched copy of the remote,
else from the repository the running plugin sits in.

Pointer: lefthook's [`remotes`](https://lefthook.dev/configuration/remotes/) and
[`extends`](https://lefthook.dev/configuration/extends/) pages; lefthook resolves a remote config's
`extends` against that config's directory
([`loadRemotes`](https://github.com/evilmartians/lefthook/blob/v2.2.2/internal/config/loader.go)),
which for a root file is the remote repository's root the remotes page names. As of 2026-11-17,
lefthook 2.2.2. Recheck on a lefthook version bump; each plugin's `git-hooks/lefthook-remote.test.sh`
checks the merged jobs under the pinned version.

## When a remote job breaks

Every repository runs the remote jobs from main, so a job broken there blocks commits or pushes in
all of them, and `block-no-verify` keeps agents from `--no-verify` and hook-manager overrides.

1. **Get past it in one clone.** A failing remote job prints the way out: an untracked
   `lefthook-local.yml` (listed in `.git/info/exclude`) that sets `skip: true` on that job,
   `<plugin>-remote-<entry>`. Lefthook merges `lefthook-local.yml` over the remotes and matches
   jobs by name. Use it only when the job itself is broken, not when it reports your change.
   A plugin with both a `format` and a `lint` entry runs them in one piped group,
   `<plugin>-remote`, format first, so a consumer's `parallel: true` cannot lint a file before
   format fixes it; a skip of either job names that group and the job inside it, as the failing
   job prints. A skip of one of those jobs written at the top level, outside its group, fails
   every commit: lefthook adds it as a job with nothing to run, and a job with no `run`, `script`
   or `group` fails before its `skip` is read (`runJob` in
   [`job.go`](https://github.com/evilmartians/lefthook/blob/v2.2.2/internal/run/controller/job.go)).
   Move such a skip under the group. Pointer: lefthook's [`lefthook-local`](https://lefthook.dev/examples/lefthook-local/),
   [`skip`](https://lefthook.dev/configuration/skip/) and
   [`group`](https://lefthook.dev/configuration/group/) pages. The guardrails content scans
   (`guardrails-remote-pre-commit-content` and `guardrails-remote-pre-push-content`, the secret and
   machine-path scans) have no per-clone skip and print none: when one is broken, the recovery is
   the revert or fix on main in step 2.
2. **Fix main.** Revert the change that broke the job, or fix it, in this repository.
3. **Pick up the fix.** `lefthook install` fetches every remote at once, whatever
   `refetch_frequency` says (`Install` in
   [`install.go`](https://github.com/evilmartians/lefthook/blob/v2.2.2/internal/command/install.go));
   `lefthook install --force` deletes the fetched copy and clones it again. Without that, a hook run
   refetches only once `refetch_frequency` has passed since the last fetch
   ([`refetch_frequency`](https://lefthook.dev/configuration/refetch_frequency/)). Then delete the
   skip.

As of 2026-11-17, lefthook 2.2.2. Recheck on a lefthook version bump.

## See what runs at each stage

`/<plugin>:setup check inspect` lists every hook each stage runs, under whichever manager the
repository uses, with the plugin's own entries timed and every other hook marked not run with the
reason. Compare the times with the [duration budgets](README.md#duration-budgets) before placing a
new check ([`inspect`](README.md#hookmanager-port)).

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

### Keep `pre-push` under the remote idle timeout

Git opens the remote connection and reads the remote refs before running `pre-push`
([githooks `pre-push`](https://git-scm.com/docs/githooks#_pre_push)), so an SSH transport sits idle
while the hook runs. On GitHub, an idle `git-receive-pack` SSH connection closes after 360 s
(measured 2026-11-21 with OpenSSH for Windows 9.5p2; recheck if GitHub changes its SSH idle
timeout). On native Windows Git Bash, fork overhead can turn a 20 s Linux `pre-push` hook into a
multi-minute run that crosses that limit.

Fix the cause rather than masking it with SSH keepalives:

- Keep `pre-push` hooks within the [duration budgets](README.md#duration-budgets) on every
  supported OS, including native Windows; move multi-minute checks to CI or on-demand commands.
- In repositories that do not use Git LFS, set `skip_lfs: true` in `lefthook.yml` so lefthook does
  not run `git lfs pre-push` against the remote on every push.
- `ServerAliveInterval` in `~/.ssh/config` only keeps an idle connection open as a stopgap and does
  not fix an over-budget hook.
