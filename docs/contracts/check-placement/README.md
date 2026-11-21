# Check placement: where each automated check runs

Owner doc for where an automated check (formatter, linter, scanner, guard) runs: a Claude Code
hook, a git `pre-commit`, `pre-push` or `commit-msg` hook, or CI. It holds the placement rubric,
the git-hook registration contract every check plugin's setup follows, and the duration budgets
each placement is measured against. The decision and the alternatives it rejected are in
[ADR 0072](../../adr/0072-place-each-check-by-coverage-cost-and-model-facing-output.md).

Status: the rubric applies now. The registration contract is specified here and implemented by the
rollout of the check plugins' git-hook entries; until a plugin's entry ships, its setup has no
`install-git-hooks` action.

Adopting the entries in a repository (trying one in a clone, a formatter's cleanup PR, sharing
with the team, declining) is in [adopting-git-hooks.md](adopting-git-hooks.md).

Related conventions: [hook-budget](../hook-budget/README.md) owns spawn counts for Claude Code
hooks and the CI ratchets that enforce them; [hook-precision](../hook-precision/README.md) owns
what a hook fires on and the stay-quiet test discipline. This doc owns where a check runs and how
long it may take there.

## The rubric

Place each check by three things: who must be covered, what it costs (measured, never guessed),
and what reaches the model.

1. **Claude Code hook** when the check must act before a tool call runs (a blocking guard) or
   changes files during the session (a formatter).
2. **git hook** when the check must cover every author: humans, other agents, and Claude Code
   sessions alike. A Claude Code hook sees only Claude Code's own tool calls.
3. **Which git hook, by measured duration:** within the commit budget, `pre-commit`; over the
   commit budget but within 60 s, `pre-push`; beyond 60 s, CI only.
4. **Report-only findings never reach the model per edit.** A shipped hook must not send a
   report-only check's findings to the model on a per-edit `PostToolUse` event. A per-edit report fires on
   in-between states the model is about to change anyway, and it can lead the model to make
   unrelated fixes during an open-ended task.
5. **Measured cost and model-facing output both decide placement.** A cheap check that prints
   to the model each edit is still misplaced; a silent check that costs seconds per edit is too.
6. **One local place per report-only check.** Each report-only check runs in exactly one local
   place, and CI re-runs it on the change only. Formatters are the one exception: they run once
   per batch in session (when within the ceiling below) and again at `pre-commit`. The opt-in
   end-of-turn hand-back is not an exception, because the
   [spelling pilot](#spelling-pilot-2026-10-15) left it off by default. markdown-format's
   default end-of-turn report is the one stated exception
   ([#11502](https://github.com/melodic-software/claude-code-plugins/issues/11502)): its lint
   runs at turn end and again at `pre-commit`, and the turn-end findings go to the user only.

   Blocking guards that stop a tool call are a separate class and are not counted here.
7. **CI never skips a check because a local hook reported a pass.** A hook can be missing,
   skipped or stale on any author's machine, so CI re-runs every check on the change.
8. **The twice-daily full-tree CI run stays** as the backstop for what scoping to the change
   misses (`.github/workflows/pr-require-checks.yml`, `schedule`).

### Formatters

- In session, a formatter runs from one `PostToolBatch` row per plugin: it rewrites the files the
  batch edited and sends no model-facing output. Claude Code shows the model the rewritten file
  itself. The row stays only while its median per fire is at most 1 s (1 s median per fire is
  the per-batch ceiling); over it, the plugin runs at `pre-commit` only.
- At `pre-commit`, every formatter rewrites the staged files and re-stages them. A file with
  unstaged changes is left alone and fails (see Rewrites in the runtime contract), because
  re-staging it would stage the author's unstaged hunks too.
- A formatter too slow for the per-batch ceiling (the `dotnet format` class) runs at `pre-commit`
  only.
- A format and lint plugin keeps the two concerns apart: a `format` entry that rewrites and a `lint`
  entry that reports, each resolved on its own ([Hooks run the shipped adapter](#hooks-run-the-shipped-adapter)). Formatting includes
  import ordering; no lint autofix runs in the batch row or at `pre-commit`.

Pointer: for `PostToolBatch` (no matcher, no `if`, one firing per batch of parallel tool calls),
see the [hooks reference](https://code.claude.com/docs/en/hooks). As of 2026-10-15, Claude Code
2.1.301. Recheck when the hooks reference changes `PostToolBatch` input fields or matching.

### Report-only checks

- The `pre-commit` gate blocks only on findings in changed lines, and only once setup installed
  it. A finding on a line the commit did not touch never blocks.
- **End-of-turn report mode (opt-in).** The same check script runs with `--worktree` (changed
  lines in the uncommitted diff against `HEAD`) from a `Stop` row behind a
  `<plugin>_end_of_turn` userConfig boolean, default `false`. Its findings exit 2, so the model
  fixes them before the turn ends; the row honors `stop_hook_active` and blocks at most once per
  turn. The hand-back stays off by default for every report-only plugin, per the
  [spelling pilot](#spelling-pilot-2026-10-15).
- **markdown-format reports at turn end by default.** Its `markdown_format_end_of_turn` has no
  default: unset, the `Stop` row exits 0 with the findings in a `systemMessage`, which the user
  sees and the model does not, and the turn ends. `true` is the hand-back above; `false` runs
  no check.

### Where verification blocks

No `TaskCompleted` gate is used. In-session blocking verification, where a plugin has it, runs
from `Stop`; for report-only checks the `pre-commit` gate stays the default blocking point, and
their `Stop` row stays opt-in as stated above. Reason: in the
[spelling pilot](#spelling-pilot-2026-10-15) the end-of-turn check never fired, because
the `pre-commit` hook caught every finding first, so a per-task gate has no measured catch to earn
its cost. Revisit when a finding reaches a commit that no hook caught.
Dissent: Lydia Hallie's talk "Rethinking Claude Code Best Practices"
([video](https://www.youtube.com/watch?v=vlfCjWuv4es)) runs each task's tests on `TaskCompleted`
and the full suite on `Stop`. Owner decision of 2026-11-12.

## The registration contract

Rule D1, split between script and agent: scripts only detect, list, diff, render snippets, verify,
and write files the plugin owns outright (copied check scripts, the plain dispatcher and its
`<event>.d/` entries, the decline key: `git config --local`, or `--global` only when the user
asks to decline across every repo). Every step that needs judgment
returns to the setup agent as data, and the agent reasons about it and applies it:

| The agent reasons and applies | Why it needs judgment |
|---|---|
| Edits to user-owned config: `lefthook.yml`, `lefthook-local.yml`, `.husky/<event>` | the file may hold the user's own jobs, comments and order |
| A pre-existing foreign hook: chain or refuse | depends on what that hook does |
| Two managers detected, or `core.hooksPath` pointing somewhere unknown | conflict resolution |
| Scope when unstated in an attended run (an unattended run stays local) | the user's intent |
| Local-to-shared migration | may collide with entries teammates already committed |
| Which install command to run for a missing tool | machine-specific provisioning |
| Acting on a drift report | the drift may be deliberate |

### Setup surface

Each check plugin's setup gains `apply install-git-hooks [scope=local|shared]`, and its `check`
runs `verify`. Setup:

- registers a named git-hook entry for lefthook, husky and plain git hooks;
- asks local-only or team-shared, and installs local-only when the question goes unanswered;
- is idempotent: a rerun with nothing changed reports `unchanged` and writes nothing;
- migrates local to shared on request, as an agent decision (D1).

The rollout ships the installer as the vendored `lib/git-hooks/install.mjs` (canonical in `lib/`,
copied into each check plugin per ADR 0019) and the check helpers as the vendored
`lib/git-hooks/check-lib.sh`; this section is the contract they implement. The check lib also
provides the partly-staged refusal helper: every rewriting check calls it before it
rewrites, so a file with unstaged changes fails with the Rewrites message below and is left alone.

### Entry manifest

`plugins/<plugin>/git-hooks/entries.json`:

```json
{
  "entries": [
    {
      "name": "lint",
      "event": "pre-commit",
      "script": "lint.sh",
      "tools": ["typos"],
      "rewrites": false
    }
  ]
}
```

`event` is `pre-commit` | `pre-push` | `commit-msg`; `rewrites: true` with `pre-push` is rejected.

A renamed plugin adds an optional top-level `earlierNames` array of its former plugin names
(`"earlierNames": ["old-name"]`), each matching the entry-name rule and never its own name.
The installer looks for artifacts and decline keys under those names only, so another plugin that
ships an entry of the same name is never touched. Each name is a migration line: the rename adds
it, and it is removed once no consumer repository still holds artifacts under that name.

A plugin that split or renamed an entry adds an optional top-level `earlierEntries` array
(`"earlierEntries": [{"from": "ruff-check", "to": ["format", "lint"]}]`). `from` is the old entry
name, never a current one; `to` names current entries. The installer reports what an install of
`from` left (under the plugin's name and each `earlierNames` name) as superseded drift, listed once
on the first `to` entry, with a copy under the plugin's own name listed as a file to remove and never
its directory. A decline of `from` counts for every `to` entry, and plan carries it to each entry's
own key. Each rule is a migration line, like an earlier name.

A plugin whose entries pick their adapter per repository
([Hooks run the shipped adapter](#hooks-run-the-shipped-adapter)) adds a top-level `ecosystems`
array of the `.claude/ecosystems/<id>.yaml` ids whose records its setup reports, and
`"resolved": true` on each such entry. For a resolved entry the installer reads the tools from the
entry script's `--resolve` rows, run under `sh`, which run nothing; `tools` is the fallback when the
script cannot answer.

An entry may add an optional `assets` array: files the script reads at run time, such as a default
config (`"assets": ["config/default-typos.toml"]`).

- Each path is relative to the plugin root: no absolute path, no `..` component.
- Base names are distinct within the entry, and none is `check-lib.sh`.
- `copy` writes each asset beside the installed script under its base name. At shared scope it
  stages the asset without the exec bit.

### Hooks run the shipped adapter

A format or lint plugin's batch row and its `format` and `lint` entries run only the adapter the
plugin ships, for a file its tool's own config opts in, through the vendored
`lib/git-hooks/resolve-tool.sh` (canonical in `lib/`, copied into each format and lint plugin and
beside each installed entry). A file no adapter's config governs gets nothing.

- **Records never run from a hook.** A `.claude/ecosystems/<id>.yaml` record's `fix-cmd` and
  `lint-cmd` ([ecosystem-commands](../ecosystem-commands/README.md)) run only when a person asks
  `/toolchain:lint` or `/toolchain:check`. No check of a record's contents can bound what its
  command executes, so a hook runs none, however the record matches the default branch. Setup
  reports a record that exists and points to `/toolchain:lint` for it.
- **Files are data.** Files reach the adapter's command as `"$@"` of `sh -c`, never as command text,
  and a name starting with `-` gains `./`. Long file lists run in chunks under the Windows
  command-line limit.
- **Findings.** A lint adapter's output lines `<path>:<line>[:<col>]: <message>`, its paths relative
  to where it ran or absolute, become repo-relative contract lines filtered to the changed lines.
  A lint command that exits non-zero with no such line fails closed and shows its output.
- **Missing tool.** The skip key is the adapter's tool. A missing tool stops only the files that
  tool would handle.

### Check-script runtime contract

| Item | Rule |
|---|---|
| Shell | `#!/bin/sh`, and POSIX sh until the script sources the check lib, its first step. The lib puts it under bash: under bash already, in POSIX mode when it started as sh, it turns POSIX mode off; under another sh it reruns the script under the first `bash` on `PATH` outside System32, Sysnative and WindowsApps, and with none, bash is a missing tool (below). A bash script the check runs itself starts through `checks_bash_run`. No hook file, dispatcher or run line names `bash` as a command: on Windows that can resolve to System32's WSL launcher. A script that needs no bash, such as guardrails' `commit-msg-convention`, stays POSIX sh throughout, so it needs no bash beside git's sh |
| Args | none from git; optional `--worktree` for the end-of-turn mode |
| Inputs | pre-commit: `git diff --cached --name-only --diff-filter=ACMR -z` plus `-U0` hunks; while a merge is in progress, an entry that lists files through `checks_files` skips a path whose staged entry (mode and blob) equals a merge head's; pre-push: refs on stdin, range `<remote-sha>..<local-sha>`, merge-base with `<remote>/HEAD` for a new branch, deletions skipped |
| Scope of findings | changed lines only; in a pre-commit merge, only the lines that differ from every parent. A file both sides changed, or whose mode differs from every head, is still listed, and a rewriting entry formats it whole |
| Missing tool | named in `git config --get checks.skipmissing` (comma list, whole-name match) and absent: `SKIPPED: <tool> (missing)` on stderr, exit 0. Otherwise an agent (`CLAUDECODE=1` or `AI_AGENT`) gets `FAIL: <tool> missing. Install: <cmd>` plus the skip line, exit 1; a human gets a one-line notice, exit 0 |
| Findings | `<path>:<line>: <message>` on stderr, exit 1 |
| Rewrites | in place, rewritten paths on stdout; a partly staged file is left alone and fails with `<path>: partly staged; format it or stage it fully, then commit` |
| Header | line 2: `# <plugin> <name> sha256:<hex>`, hash of the source script plus check lib and any assets (defined under Drift) |

Under lefthook, a `pre-push` check gets the refs only with `use_stdin: true` in a hook whose jobs run
sequentially: lefthook caches stdin and replays it to each such job in turn, while parallel jobs
read one shared stream. A check that gets no refs falls back to the current branch against its
upstream, and checks nothing on a branch with no upstream. Pointer: lefthook's
[`cached_reader.go`](https://github.com/evilmartians/lefthook/blob/v2.2.2/internal/run/controller/utils/cached_reader.go);
its [`use_stdin`](https://lefthook.dev/configuration/use_stdin) page still says only one job receives
stdin. As of 2026-10-24, lefthook 2.2.2. Recheck when a lefthook release changes that file or the
page's note.

### The skip key: `checks.skipmissing`

The only way to skip a check is one git config key, defined here once:

```sh
git -c checks.skipmissing=<tool>[,<tool>] commit ...
```

- Every check script reads it under every hook manager, through `git config --get`.
- It is honored only for a tool the script finds absent. Naming a tool that is installed changes
  nothing: the check still runs.
- Every skip prints `SKIPPED: <tool> (missing)` on stderr.
- No environment marker loosens it, and there is no other skip: no environment variable, no
  `--no-verify`, no `core.hooksPath` redirect. Guardrails allows exactly this key and keeps
  blocking the other two.
- No `Skipped-Checks` commit trailer is written, since CI re-runs every check on the change.

An agent's missing tool is provisioned first: setup installs it locally, and a cloud
environment's setup script installs it there. Setup's `check` lists every enabled entry whose tool
is missing, so a lane or cloud setup script can provision it before an unattended session runs.

**The skip and the human missing-tool pass rely on CI re-running the check.** A consumer
repository without a CI job that runs the same tool on the change should not skip, and should not
rely on the human pass. Setup's agent notes, per entry, when no CI workflow in the consumer
repository runs that entry's tool. Agent detection reads only `CLAUDECODE` and `AI_AGENT`, so an
agent that clears them gets the human pass; CI re-running the check is the backstop.

That a hook sees a `git -c` value is measured (git 2.53.0, lefthook 2.2.1, husky 9.1.7, 2026-10-15)
but not documented: [git-config](https://git-scm.com/docs/git-config) documents only
`GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>` and `GIT_CONFIG_VALUE_<n>`. The check lib's test asserts
the propagation, so a git change fails a test rather than silently dropping the skip. Recheck when
the consumer git floor moves.

### HookManager port

```text
detect(repo)                  -> { manager: "lefthook"|"husky"|"plain"|"conflict", evidence[], variant? }
list(repo)                    -> [{ entryId, event, scope, stamp }]
inspect(repo, runs?)          -> { manager, variant?, evidence[], hooksDir, stages[{ event, installed, hookFile, items[] }] }   # read-only
plan(repo, entries, scope)    -> { actions[], decisions[] }
copy(repo, entry, scope)      -> "installed" | "refreshed" | "unchanged" | "blocked" | "unsafe-path" | "stage-failed"   # plugin-owned files only
decline(repo, entryId)        -> sets the git config --local key (--global: the global one)
```

`plan` returns `actions` the script applies (plugin-owned files) and `decisions` the agent applies
(D1). Entry names, events and scopes are manager-neutral; each manager's file format stays inside
its adapter. `detect` also recognizes other hook managers (the pre-commit framework, simple-git-hooks,
overcommit, husky v4) and returns them as conflict decisions. A set `core.hooksPath` is treated as
husky or foreign, never as plain. A `.husky/task-runner.json` marks Husky.Net: `detect` returns
`husky` with `variant: "husky.net"`, since Husky.Net runs `.husky/<event>` as husky does and the
husky adapter drives it. One difference: Husky.Net points `core.hooksPath` at `.husky` itself, so
git runs `.husky/<event>` directly and skips it unless it is executable.

**`inspect`.** For each git hook stage, `inspect` lists every item that runs, under whichever
manager the repository uses: plain dispatcher markers and a chained `<event>.pre-checks`, each
command line of `.husky/<event>` (and the Husky.Net tasks a `husky run --group` or `--name` line
selects), the lefthook jobs `lefthook dump` reports, git config hooks (the events left after an
empty-value reset; one with `hook.<name>.enabled=false` is reported disabled), and any other hook
file. `installed` says whether git finds an executable hook file for the stage. An item that is a
stamped entry copy names its plugin and entry; a script path from a command, marker or lefthook
job is followed only inside the work tree or the hooks directory. Only the calling plugin's own entries, on their own event, that
rewrite nothing and whose tools are present are run, and only from an installed copy whose script,
lib and assets hash to what the plugin ships now: a stamp alone proves nothing, so an edited or
forged copy is never run and an older one gets a refresh hint. They run on the staged set (`pre-commit`),
a message file outside the repository (`commit-msg`) or the branch against its upstream
(`pre-push`), and get `measured: { medianMs, minMs, maxMs, runs, input, exitCodes }`; every other
item gets `notMeasured` with the reason. `inspect` itself writes nothing in the repository; a
timed entry does only what it does in a real hook run. Its numbers feed
the [duration budgets](#duration-budgets) for placing a check.

**`hooks-path-owned`.** When `core.hooksPath` hands the local hooks directory to another tool (any
value except the plain shared `.githooks`), `plan` returns only one decision,
`{kind: "hooks-path-owned", hooksPath, dir}`, with empty `actions`. `copy --scope local` then
writes nothing, prints `{"installed":[],"decisions":[...]}` with that decision, exits 1, and
reports status `blocked`. The setup agent decides what to do with the other tool's hooks (D1).

**`unsafe-path`.** A cloned repository's contents are untrusted. When any file `copy` would write
for an entry, or a directory on the way to it below the work tree's top level (or below the local
hooks directory), is a symlink, `plan` returns `{kind: "unsafe-path", entry, file}` and `copy`
writes nothing for that entry, reports status `unsafe-path`, and exits 1. Only the exact dispatcher,
or one an earlier release wrote (which `copy` replaces), counts as the plugin's own; a hook that
carries its sentinel line but differs is a `modified` decision, overwritten only by `copy --force`. The installer reads repository files only when they
are regular files of at most 1 MiB, never through a final symlink; anything else reads as absent.

**`stage-failed`.** A shared install stages what it writes; when `git add` fails (an ignored path,
a locked index), `copy` reports `stage-failed` and exits 1, since the team would not receive the
files. A plain marker counts as wired only while it names its entry's script.

### Where installed copies live

Git hooks run outside Claude Code, with no `CLAUDE_PLUGIN_ROOT`, so install copies the check script
and the check lib into the repository instead of pointing at the plugin cache.

| Manager | Local scope | Shared scope |
|---|---|---|
| lefthook | `lefthook-local.yml` | committed `.githooks/<plugin>/` plus `lefthook.yml` |
| husky | none: setup offers shared only and says why | committed `.githooks/<plugin>/` plus `.husky/<event>` |
| plain | a dispatcher per event in `$(git rev-parse --git-path hooks)`, running every entry in `<event>.d/` | committed `.githooks/` with the dispatcher, activated per clone (below) |

**The lefthook remote copies nothing.** With lefthook, a shared install prefers `plan --scope
remote`: the committed `lefthook.yml` carries one `remotes:` entry naming this repository's root
`lefthook-remote.yml`, which extends every plugin's `git-hooks/lefthook-remote.yml`, and each clone
runs the entries from lefthook's fetched copy of main. Each job is `<plugin>-remote-<entry>`, so it
never merges with a shared-copy job, and `verify` counts an entry `ok` once that remote is fetched
and the event's hook is installed. Adopting it, skipping one job in a clone, and recovering from a
broken job: [adopting-git-hooks.md](adopting-git-hooks.md#share-it-through-the-lefthook-remote).

Plain hooks: the dispatcher keeps a pre-existing hook as `<event>.pre-checks` and runs it first,
then each entry whose first line is `#!/bin/sh` with `sh`, as the lefthook and husky run lines
`plan` renders do. An entry an earlier release installed runs by its own first line until `copy`
refreshes it.

**Plain shared hooks need a per-clone step.** No committed file can set `core.hooksPath`, so each
clone runs `git config core.hooksPath .githooks` once; setup does it as a D1 decision. Local
entries under a plain-shared repository go to `.githooks/local/<event>.d/`, excluded through
`git rev-parse --git-path info/exclude`. A teammate who never runs that command gets no hooks, so
for a team with non-Claude authors, recommend lefthook or husky: both install the hooks from
committed config through their own install step. Setting `core.hooksPath` also activates what
others put under `.githooks/`, so before the `hooks-path` decision `plan` returns
`{kind: "shared-entries", files}` listing each `<event>.d/` marker other than one of the plugin's
own entries naming its script, each `*.pre-checks` hook, each other hook file (a name with no dot
that is not the dispatcher) and each tracked file under `.githooks/local/`; with none present it
returns no such decision.

**Committed hook config runs the checked-out branch's code.** Lefthook and husky read their config,
and plain shared hooks read `.githooks/`, from the branch that is checked out. Once a clone has
installed hooks, a commit or push on a contributor's branch runs whatever that branch puts in
`lefthook.yml`, `lefthook-local.yml`, `.lefthook/`, `.lefthook-local/`, `.husky/` or `.githooks/`.
Pinning check scripts to the merge-base does not
reach the config file itself. Before committing or pushing on a branch you do not trust, read its
diff to those paths: pre-commit and commit-msg hooks run at commit, before any push.

### Drift: the content-hash stamp

Line 2 of every installed copy carries `# <plugin> <name> sha256:<hex>`. The hash is sha256 over
the LF-normalized source script bytes, then a NUL, then the LF-normalized check lib, then, for
each asset in manifest order, a NUL and that asset's LF-normalized bytes. The stamp is a content hash, not a plugin version: a
version stamp would flag drift on every release, and at shared scope each rerun would add a commit
to every consumer repository.

`verify` reports one of five states per entry, plus one `superseded` row per declared earlier name an entry has artifacts under:

| State | Meaning | Output |
|---|---|---|
| ok | stamp equals the current source hash | silent |
| stale | stamp differs from the current source hash (a changed source script, check lib or asset) | drift line |
| modified | the installed copy, or an installed asset, no longer hashes to its stamp | drift line; the agent decides (D1) |
| missing | not installed and not declined | drift line |
| declined | `checks.<plugin>.<name>.declined` true at any git config scope; unset, the same entry's key under a declared earlier name (`earlierNames`) true by git's precedence (its detail names the carry-over; that key false is an opt-in, as the entry's own false is); both unset, `checks.git-hooks.declined` true | silent until `verify` runs by hand |
| superseded | an artifact of this entry under a former name the plugin declares in `earlierNames`, as an install made before the rename leaves: a copy whose stamp names the entry, its `<event>.d/` marker, a lefthook job running it, a config-hook copy under the user git config directory with its `includeIf` and `hook.<name>-<entry>` keys, or a decline key under the earlier name in this clone's own local or worktree config, or one whose value this clone has not yet carried to its own local key | drift line naming each artifact; `plan` returns them as a `superseded` decision, and the setup agent removes them and carries this clone's resolved decline or opt-in to its own local key on the user's yes (D1). An earlier-name decline line in a system or global file, or a file one includes, is never edited: `plan` reports it with the command to remove it once every clone relying on it has its own key, and `verify` stays silent about it once this clone has one |

Drift line, shown to the user only:

```text
<plugin>: git hook <name> <state>; run /<plugin>:setup apply install-git-hooks
<plugin>: git hook <name> left under an earlier plugin name (remove <dir> and <marker> and any hook-manager line that runs <script>; ...); run /<plugin>:setup apply install-git-hooks
```

The SessionStart drift check runs inside the plugin's `prerequisites.mjs probe`, which harness-ops'
one SessionStart runner starts for each plugin that declares `session_probe` in its
`prerequisites.json` ([prerequisites](../prerequisites/README.md#the-checker)), so it adds no
SessionStart row. A decline is recorded per clone by default, never committed; git shares
`.git/config` and the hooks directory across every worktree of a clone, so the decline has the
same scope as the hook it declines. A global decline (`decline --global`, or the master key
`checks.git-hooks.declined` that declines every entry of every plugin) covers every clone; a
clone opts one entry back in by setting its own key to `false`, which `copy` does when it
installs over a global decline.

### Tests

Every git-hook entry has a test and a measured cost row in the table below. A check script's test
builds a throwaway repository, stages a file, runs the script, and asserts exit code and stderr;
each check carries at least one stay-quiet case ([hook-precision](../hook-precision/README.md)).

## spelling pilot (2026-10-15)

Claude Code 2.1.301, Sonnet, headless, one multi-edit task over four files with seeded misspellings
in a passage the prompt asked to paste verbatim, then a commit; user settings excluded so only the
plugin under test loaded, and file changes allowed only through Edit and Write.

Arms: control (today's per-edit `PostToolUse` report), precommit (per-edit row removed, `pre-commit`
entry installed) and eot (precommit plus the end-of-turn check on). A run completed when the commit
held all four edits and was typo-free. Control ran n=5. The end-of-turn verdict was decided by one
run at n=5, so the one-run-margin rule reran both treatment arms, to n=10 each.

| Arm | n | Completed | Median wall s (min-max) | Failed edits | Fixed before turn end |
|---|---|---|---|---|---|
| control | 5 | 0 | 23.7 (22.4-26.0) | 0 | 0 |
| precommit | 10 | 6 | 24.8 (21.2-28.2) | 0 | 6 |
| eot | 10 | 5 | 24.55 (21.9-29.1) | 0 | 5 |

Regression rule: an arm regresses if it completes fewer tasks than control, or if its median wall
time or failed edits is worse than control's by more than control's own min-max spread (3.6 s wall,
0 failed edits).

Verdicts:

- **The report moves off per-edit.** Both arms pass: precommit completed 6/10 and eot 5/10 against
  control's 0/5, with median wall +1.1 s and +0.9 s against a 3.6 s spread, and no failed edits in
  any arm.
- **End-of-turn stays opt-in, default off, for every report-only plugin.** It did not get findings
  fixed before turn end in more runs than precommit (5 against 6). The pilot measured the exit-2
  hand-back, so the verdict covers that mode; markdown-format's default report to the user is
  outside it.

Caveats:

- The end-of-turn check never fired in any run: the model always committed within the turn, so the
  `pre-commit` hook caught every finding first. Testing that mode needs a task that ends a turn with
  changes uncommitted.
- Timing and wording are confounded. In every control run the per-edit report reached the model and
  the model allow-listed the words instead of fixing them; the per-edit message suggests only
  allow-listing, while the `pre-commit` message says to fix the words first. This pilot cannot
  separate the two causes.
- Failed edits were 0 in every run, so that part of the rule had no signal to detect.

## Duration budgets

Each row is measured on the host named in its row. Other hosts re-measure; CI does not enforce
durations ([hook-budget](../hook-budget/README.md) enforces counts). Placement shipped by this
marketplace comes from these rows.

| Budget | Value | Basis |
|---|---|---|
| Per-batch formatter (`PostToolBatch`) | 1 s median per fire | judgment from the measured spread; revisit after the rollout's per-batch measurements |
| Commit (`pre-commit` set) | 10 s for all 11 shipped `pre-commit` entries run in a row | judgment from the measured set: 0.91 s on 1 file, 1.91 s on 10, 9.6 s on a 45-file mixed set and 96.3 s on a 44-file set (per-check timings below); 10 s keeps the mixed set inside and `reference-verify`'s 12.2 s on 44 files outside, as its move to `pre-push` decided |
| Push (`pre-push`) | 60 s | judgment from the measured spread; beyond it, CI only |

### Measured rows

| Hook | Placement | Measured | Host | Date |
|---|---|---|---|---|
| spelling `pre-commit` entry (typos 1.51.1, plain dispatcher), staged sets from real `origin/main` commits | pre-commit | 1 file 0.039 s (0.038-0.040); 10 files 0.125 s (0.122-0.133); 44 files 0.508 s (0.491-0.681) | reference host (Linux, WSL2, 32 CPUs) | 2026-10-15 |
| guardrails `commit-msg-convention` entry, one message | commit-msg | 10 ms median (9-11) | reference host (Linux, WSL2) | 2026-10-16 |
| guardrails `pre-commit-content` entry, staged sets from real `origin/main` commits | pre-commit | 1 file 0.039 s (0.036-0.040); 10 files 0.311 s (0.298-0.337); 44 files 1.277 s (1.206-1.450), re-measured 1.302 s (1.209-1.467) once it was the only guardrails `pre-commit` entry | reference host (Linux, WSL2) | 2026-10-16 |
| code-tidying `comment-lint` entry (pygments 2.19.2, installed local copy, `comment_lint: report`), staged sets from real `origin/main` commits (code files 1 of 1, 6 of 10, 24 of 44) | pre-commit | 1 file 0.331 s (0.325-0.348); 10 files 0.422 s (0.412-0.438); 44 files 0.939 s (0.927-1.055) | reference host (Linux, WSL2, 32 CPUs) | 2026-11-14 |
| guardrails `reference-verify` entry, the 44-file `origin/main` commit (37 of its files are `.md`/`.sh`) as one pushed range | pre-push | 10.6 s median (10.1-12.5); 15.7 s on the first run in a clone, which builds the deleted-path cache | reference host (Linux, WSL2) | 2026-10-16 |
| guardrails `reference-verify` entry at `pre-commit`, before the move, same staged sets (1 file is not `.md`/`.sh`) | pre-commit until it moved to pre-push: 44 files is over the commit budget | 1 file 0.018 s (0.017-0.019); 10 files 1.169 s (1.109-1.271), 11.0 s on the first run in a clone; 44 files 12.2 s (10.6-17.0) | reference host (Linux, WSL2) | 2026-10-16 |
| `scripts/check-affected.sh --no-fetch` (this repository) | pre-push until moved to CI / on-demand (over budget on native Windows) | 15.5 s median on a 28-file range; 0.52 s on one file | reference host (Linux, WSL2) | 2026-10-15 |
| actionlint, per edit (`.github/workflows/*.yml`) | PostToolUse until removed; now pre-commit | 44 ms median (43-47) | reference host (Linux, WSL2) | 2026-10-15 |
| bash-format, per edit (`.sh`, configured) | PostToolUse until replaced; now PostToolBatch and pre-commit | 64 ms median (62-68) | reference host (Linux, WSL2) | 2026-10-15 |
| javascript-format, per edit (`.ts`, configured) | PostToolUse until replaced; now PostToolBatch and pre-commit | 62 ms median (60-77) | reference host (Linux, WSL2) | 2026-10-15 |
| markdown-format, per edit (`.md`, configured) | PostToolUse until replaced; now PostToolBatch and pre-commit | 180 ms median (174-186) | reference host (Linux, WSL2) | 2026-10-15 |
| powershell-format, per edit (`.ps1`, configured) | PostToolUse until removed; now pre-commit | 973 ms median (918-1,026) | reference host (Linux, WSL2) | 2026-10-15 |
| python-format, per edit (`.py`, configured) | PostToolUse until replaced; now PostToolBatch and pre-commit | 75 ms median (73-83) | reference host (Linux, WSL2) | 2026-10-15 |
| spelling, per edit (`.md`) | PostToolUse until removed; now pre-commit | 59 ms median (56-63) | reference host (Linux, WSL2) | 2026-10-15 |

The per-edit rows are the `PostToolUse` rows each plugin's `hooks/hooks.json` ran on 2026-10-15,
timed with a sample that needs work (hyperfine, 2 warmups, 10 runs; a 15 ms spawn baseline is
included). They are the baseline the git-hook entries and `PostToolBatch` rows replaced; each new
entry adds its own row here when it ships.

### Per-check timings

Method: hyperfine 1.21.0, 1 warmup, 10 runs for `pre-commit` and 3 for `pre-push`, median with
min-max. A `pre-commit` sample is a real `origin/main` commit staged on its parent, re-staged before
every run, with each entry script run directly from a copy of `origin/main`. A `pre-push` sample is
`scripts/check-affected.sh --no-fetch --base <parent>` at a real commit, or at a one-line edit to
`scripts/check-cost-figures.sh` on `origin/main`. Host: Linux, WSL2, 24 CPUs; shellcheck 0.11.0,
shfmt 3.14.1, typos 1.52.2, markdownlint-cli2 0.24.0, actionlint 1.7.12. Samples: 1 file
(`55c8ce6fea`, one `.sh`), 10 files (`dedc4fd990`), 44 files (`83fb17c179`, 24 `.sh`, 22 of them
copies of `hook-utils.sh`), 45 files (`5fdcd660b4`, 24 `.mjs`, 12 workflows); 28 files
(`4e73c874b5`).

| Check | Stage | Median (min-max) | Sample | Host | Date |
|---|---|---|---|---|---|
| all 11 entries in a row | pre-commit | 0.91 s; 1.91 s; 96.3 s (93.1-102.8); 9.6 s (9.5-9.7) | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| bash-format `shell-check` | pre-commit | 0.32 s; 0.66 s; 98.9 s (93.8-108.7); 6.3 s | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| bash-format `lint`, one ShellCheck call per batch (before) | pre-commit | 0.33 s (0.32-0.34); 0.68 s (0.65-0.71); 22.0 s (21.8-22.3), 5 runs, peak RSS 4.66 GB | 1; 10; 44 files | Linux, WSL2, 24 CPUs | 2026-11-17 |
| bash-format `lint`, parallel lanes, dataflow analysis off above 2,000 lines (after) | pre-commit | 0.35 s (0.34-0.38); 0.69 s (0.68-0.82); 2.99 s (2.94-3.01), 5 runs, peak RSS 0.33 GB | 1; 10; 44 files | Linux, WSL2, 24 CPUs | 2026-11-17 |
| bash-format `format` | pre-commit | 0.42 s (0.42-0.43), 5 runs | 44 files | Linux, WSL2, 24 CPUs | 2026-11-17 |
| code-tidying `comment-lint` | pre-commit | 0.37 s; 0.45 s; 0.17 s; 1.72 s | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| spelling `typos-check` | pre-commit | 0.06 s; 0.13 s; 0.86 s; 0.36 s | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| markdown-format `markdown-check` | pre-commit | 0.01 s; 0.40 s; 0.35 s; 0.55 s | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| guardrails `pre-commit-content` | pre-commit | 0.06 s; 0.14 s; 0.39 s; 0.37 s | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| actionlint `actionlint-check` | pre-commit | 0.01 s; 0.01 s; 0.01 s; 0.10 s | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| instruction-placement `index-check` | pre-commit | 0.03 s on every sample | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| javascript-format, python-format, go-format, powershell-format entries | pre-commit | 0.01-0.02 s each on every sample (no file of their types, or a few `.mjs`) | 1; 10; 44; 45 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| `scripts/check-affected.sh` lint tier, which includes the `plugin-imports` boundary check | CI / on-demand (previously pre-push) | 4.0 s (4.0-4.1); 18.6 s (18.2-18.6) | 1 file; 28 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| `scripts/check-plugin-imports.sh` alone | CI / on-demand (previously pre-push) | 1.24 s (1.21-1.30), 10 runs | whole tree | Linux, WSL2, 24 CPUs | 2026-11-16 |
| guardrails `pre-push-content` | pre-push | 0.17 s (0.15-0.19), 5 runs | 28 files, one unpushed commit | Linux, WSL2, 24 CPUs | 2026-11-16 |
| guardrails `reference-verify` | pre-push | 1.25 s (1.18-1.27), 5 runs | 28 files, one unpushed commit | Linux, WSL2, 24 CPUs | 2026-11-16 |
| bash-format `lint-full`, dataflow analysis on the pushed scripts over 2,000 lines | pre-push | 11.8 s (10.7-13.0), 5 runs, largest ShellCheck process 5.38 GB | 44 files (`83fb17c179` on its parent as one pushed range, work tree at the tip) | Linux, WSL2, 24 CPUs | 2026-11-17 |
| `scripts/check-affected.sh --tests` | CI only | 4.5 s, 0 suites; 94.7 s (89.5-96.5), 10 suites; 164.3 s (159.4-165.8), 24 suites | 1 file (`151a7b0c0c`, data); 1 file (script edit); 28 files | Linux, WSL2, 24 CPUs | 2026-11-16 |
| `scripts/check-affected.sh --no-fetch` lint tier (before optimization) | CI / on-demand | 191.0 s (3 files, `8da0aa01d2`); 328.0 s (32 files, `81495b571d`) | 3 files; 32 files | Windows, Git Bash (`git 2.55.0.windows.3`) | 2026-11-21 |
| `scripts/check-cross-plugin-source-drift.sh --check` (before; after) | CI / on-demand | 86.6 s; 2.9-6.5 s | whole tree | Windows, Git Bash | 2026-11-21 |
| `scripts/check-changelog-parity.sh` `--check` + `--check-order` (before; after) | CI / on-demand | 18.7 s + 20.6 s; 0.37 s + 1.45 s | whole tree | Windows, Git Bash | 2026-11-21 |
| `scripts/check-plugin-imports.sh` (before; after) | CI / on-demand | 39.2 s; 25.9 s | whole tree | Windows, Git Bash | 2026-11-21 |
| `scripts/check-cost-figures.sh --check` (before; after) | CI / on-demand | 20.1 s; 7.1 s | whole tree | Windows, Git Bash | 2026-11-21 |
| `scripts/check-as-of-recheck.sh --check` (before; after) | CI / on-demand | 6.5 s; 3.1 s | whole tree | Windows, Git Bash | 2026-11-21 |
| guardrails `pre-push-content` | pre-push | 0.54 s (3 files); 0.67 s (32 files) | `8da0aa01d2`; `81495b571d` | Windows, Git Bash | 2026-11-21 |
| guardrails `reference-verify` | pre-push (skipped on Windows in this repository's `lefthook.yml`) | 43.6-66.8 s (3 files); 47.5 s (32 files) | `8da0aa01d2`; `81495b571d` | Windows, Git Bash | 2026-11-21 |

On Linux WSL2, `guardrails` `pre-push-content` (0.17 s) and `reference-verify` (1.25 s) total
1.42 s on the 28-file sample, while `scripts/check-affected.sh` alone took 18.6 s.
On native Windows Git Bash, process-spawn overhead pushes `scripts/check-affected.sh` to
191-328 s (over both the 60 s push budget and, combined with `reference-verify`, GitHub's 360 s
idle SSH timeout for `git-receive-pack`) and `reference-verify` alone to 44-67 s. This
repository's `lefthook.yml` therefore sets `skip_lfs: true`, keeps
`guardrails-remote-pre-push-content` (~0.5-0.7 s on Windows) active everywhere, skips
`guardrails-remote-reference-verify` on Windows hosts (preserving its 1.25 s run on Linux), and
leaves `scripts/check-affected.sh` to CI and on-demand runs. Change-scoped tests stay in CI: `--tests`
adds 1.0 s on a change that selects no suite, 90.7 s on a one-file script edit and 145.7 s on the
28-file change, so a typical push goes over the 60 s budget.

The shipped `pre-commit` set took 96.3 s on the 44-file sample, a real `origin/main` commit, over
the commit budget and the push budget. bash-format's `shell-check` alone measured 98.9 s:
shellcheck takes 1.7 s on one copy of the 5,174-line `hook-utils.sh`, and the commit changes 22 of
them. Linting identical copies once brought it to 22.0 s, most of it ShellCheck's dataflow analysis
of two scripts: 12.5 s for the 6,383-line `lib/hook-utils.test.sh` and 11.3 s for
`block-root-delete-target.sh`, 2.9 s each without it. The `lint` entry now runs ShellCheck in
parallel lanes and turns dataflow analysis off above 2,000 lines, the size the ShellCheck manual
names for it; 3.0 s. Those scripts' dataflow checks (SC2218, SC2319, SC2320 and SC2324) move to the
`lint-full` pre-push entry, which lints each pushed script over 2,000 lines with full analysis in
11.8 s on that sample. Added to `reference-verify`'s 10.6 s on the same sample (the 2026-10-16
row above), that is 22.4 s, inside the 60 s push budget.
