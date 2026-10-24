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
   in-between states the model is about to change anyway, and it can pull an open-ended task
   toward unrelated fixes.
5. **Measured cost and model-facing output both decide placement.** A cheap check that prints
   to the model each edit is still misplaced; a silent check that costs seconds per edit is too.
6. **One local place per report-only check.** Each report-only check runs in exactly one local
   place, and CI re-runs it on the change only. Formatters are the one exception: they run once
   per batch in session (when within the ceiling below) and again at `pre-commit`. The opt-in
   end-of-turn check is not an exception, because the
   [typos-format pilot](#typos-format-pilot-2026-10-15) left it off by default.

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
  turn. It stays off by default for every report-only plugin, per the
  [typos-format pilot](#typos-format-pilot-2026-10-15).

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
      "name": "typos-check",
      "event": "pre-commit",
      "script": "typos-check.sh",
      "tools": ["typos"],
      "rewrites": false
    }
  ]
}
```

`event` is `pre-commit` | `pre-push` | `commit-msg`; `rewrites: true` with `pre-push` is rejected.

An entry may add an optional `assets` array: files the script reads at run time, such as a default
config (`"assets": ["config/default-typos.toml"]`).

- Each path is relative to the plugin root: no absolute path, no `..` component.
- Base names are distinct within the entry, and none is `check-lib.sh`.
- `copy` writes each asset beside the installed script under its base name. At shared scope it
  stages the asset without the exec bit.

### Check-script runtime contract

| Item | Rule |
|---|---|
| Args | none from git; optional `--worktree` for the end-of-turn mode |
| Inputs | pre-commit: `git diff --cached --name-only --diff-filter=ACMR -z` plus `-U0` hunks; pre-push: refs on stdin, range `<remote-sha>..<local-sha>`, merge-base with `<remote>/HEAD` for a new branch, deletions skipped |
| Scope of findings | changed lines only |
| Missing tool | named in `git config --get checks.skipmissing` (comma list, whole-name match) and absent: `SKIPPED: <tool> (missing)` on stderr, exit 0. Otherwise an agent (`CLAUDECODE=1` or `AI_AGENT`) gets `FAIL: <tool> missing. Install: <cmd>` plus the skip line, exit 1; a human gets a one-line notice, exit 0 |
| Findings | `<path>:<line>: <message>` on stderr, exit 1 |
| Rewrites | in place, rewritten paths on stdout; a partly staged file is left alone and fails with `<path>: partly staged; format it or stage it fully, then commit` |
| Header | line 2: `# <plugin> <name> sha256:<hex>`, hash of the source script plus check lib and any assets (defined under Drift) |

A `pre-push` check that shares the hook with another job under lefthook may get no refs: lefthook
hands stdin to only one `use_stdin: true` job. The check lib then falls back to the current branch
against its upstream, and checks nothing on a branch with no upstream. Pointer: lefthook's
[`use_stdin`](https://lefthook.dev/configuration/use_stdin) page. As of 2026-10-16, lefthook 2.2.1.
Recheck when that page drops its one-job note.

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
detect(repo)                  -> { manager: "lefthook"|"husky"|"plain"|"conflict", evidence[] }
list(repo)                    -> [{ entryId, event, scope, stamp }]
plan(repo, entries, scope)    -> { actions[], decisions[] }
copy(repo, entry, scope)      -> "installed" | "refreshed" | "unchanged" | "blocked" | "unsafe-path" | "stage-failed"   # plugin-owned files only
decline(repo, entryId)        -> sets the git config --local key (--global: the global one)
```

`plan` returns `actions` the script applies (plugin-owned files) and `decisions` the agent applies
(D1). Entry names, events and scopes are manager-neutral; each manager's file format stays inside
its adapter. `detect` also recognizes other hook managers (the pre-commit framework, simple-git-hooks,
overcommit, husky v4) and returns them as conflict decisions. A set `core.hooksPath` is treated as
husky or foreign, never as plain.

**`hooks-path-owned`.** When `core.hooksPath` hands the local hooks directory to another tool (any
value except the plain shared `.githooks`), `plan` returns only one decision,
`{kind: "hooks-path-owned", hooksPath, dir}`, with empty `actions`. `copy --scope local` then
writes nothing, prints `{"installed":[],"decisions":[...]}` with that decision, exits 1, and
reports status `blocked`. The setup agent decides what to do with the other tool's hooks (D1).

**`unsafe-path`.** A cloned repository's contents are untrusted. When any file `copy` would write
for an entry, or a directory on the way to it below the work tree's top level (or below the local
hooks directory), is a symlink, `plan` returns `{kind: "unsafe-path", entry, file}` and `copy`
writes nothing for that entry, reports status `unsafe-path`, and exits 1. Only the exact dispatcher
counts as the plugin's own; a hook that carries its sentinel line but differs is a `modified`
decision, overwritten only by `copy --force`. The installer reads repository files only when they
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

Plain hooks: the dispatcher keeps a pre-existing hook as `<event>.pre-checks` and runs it first.

**Plain shared hooks need a per-clone step.** No committed file can set `core.hooksPath`, so each
clone runs `git config core.hooksPath .githooks` once; setup does it as a D1 decision. Local
entries under a plain-shared repository go to `.githooks/local/<event>.d/`, excluded through
`git rev-parse --git-path info/exclude`. A teammate who never runs that command gets no hooks, so
for a team with non-Claude authors, recommend lefthook or husky: both install the hooks from
committed config through their own install step.

**Committed hook config runs the checked-out branch's code.** Lefthook and husky read their config,
and plain shared hooks read `.githooks/`, from the branch that is checked out. Once a clone has
installed hooks, a commit or push on a contributor's branch runs whatever that branch puts in
`lefthook.yml`, `.lefthook/`, `.husky/` or `.githooks/`. Pinning the check scripts to the
merge-base, as this repository's pre-push job does, does not reach the config file itself. Before
committing or pushing on a branch you do not trust, read its diff to those paths: pre-commit and
commit-msg hooks run at commit, before any push.

### Drift: the content-hash stamp

Line 2 of every installed copy carries `# <plugin> <name> sha256:<hex>`. The hash is sha256 over
the LF-normalized source script bytes, then a NUL, then the LF-normalized check lib, then, for
each asset in manifest order, a NUL and that asset's LF-normalized bytes. The stamp is a content hash, not a plugin version: a
version stamp would flag drift on every release, and at shared scope each rerun would add a commit
to every consumer repository.

`verify` reports one of five states per entry:

| State | Meaning | Output |
|---|---|---|
| ok | stamp equals the current source hash | silent |
| stale | stamp differs from the current source hash (a changed source script, check lib or asset) | drift line |
| modified | the installed copy, or an installed asset, no longer hashes to its stamp | drift line; the agent decides (D1) |
| missing | not installed and not declined | drift line |
| declined | `checks.<plugin>.<name>.declined` true at any git config scope, or unset with `checks.git-hooks.declined` true | silent until `verify` runs by hand |

Drift line, shown to the user only:

```text
<plugin>: git hook <name> <state>; run /<plugin>:setup apply install-git-hooks
```

The SessionStart drift check runs inside each plugin's existing `prerequisites.mjs probe` row, so
it adds no SessionStart spawn. A decline is recorded per clone by default, never committed; git shares
`.git/config` and the hooks directory across every worktree of a clone, so the decline has the
same scope as the hook it declines. A global decline (`decline --global`, or the master key
`checks.git-hooks.declined` that declines every entry of every plugin) covers every clone; a
clone opts one entry back in by setting its own key to `false`, which `copy` does when it
installs over a global decline.

### Tests

Every git-hook entry has a test and a measured cost row in the table below. A check script's test
builds a throwaway repository, stages a file, runs the script, and asserts exit code and stderr;
each check carries at least one stay-quiet case ([hook-precision](../hook-precision/README.md)).

## typos-format pilot (2026-10-15)

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
  fixed before turn end in more runs than precommit (5 against 6).

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
| Commit (`pre-commit` set) | set from one staged-file run of every shipped `pre-commit` entry together on the same 44-file set, measured when the rollout of the remaining check plugins lands | until then the per-entry rows below stand |
| Push (`pre-push`) | 60 s | judgment from the measured spread; beyond it, CI only |

### Measured rows

| Hook | Placement | Measured | Host | Date |
|---|---|---|---|---|
| typos-format `pre-commit` entry (typos 1.51.1, plain dispatcher), staged sets from real `origin/main` commits | pre-commit | 1 file 0.039 s (0.038-0.040); 10 files 0.125 s (0.122-0.133); 44 files 0.508 s (0.491-0.681) | reference host (Linux, WSL2, 32 CPUs) | 2026-10-15 |
| guardrails `commit-msg-convention` entry, one message | commit-msg | 10 ms median (9-11) | reference host (Linux, WSL2) | 2026-10-16 |
| guardrails `pre-commit-content` entry, staged sets from real `origin/main` commits | pre-commit | 1 file 0.039 s (0.036-0.040); 10 files 0.311 s (0.298-0.337); 44 files 1.277 s (1.206-1.450), re-measured 1.302 s (1.209-1.467) once it was the only guardrails `pre-commit` entry | reference host (Linux, WSL2) | 2026-10-16 |
| guardrails `reference-verify` entry, the 44-file `origin/main` commit (37 of its files are `.md`/`.sh`) as one pushed range | pre-push | 10.6 s median (10.1-12.5); 15.7 s on the first run in a clone, which builds the deleted-path cache | reference host (Linux, WSL2) | 2026-10-16 |
| guardrails `reference-verify` entry at `pre-commit`, before the move, same staged sets (1 file is not `.md`/`.sh`) | pre-commit until it moved to pre-push: 44 files is over the commit budget | 1 file 0.018 s (0.017-0.019); 10 files 1.169 s (1.109-1.271), 11.0 s on the first run in a clone; 44 files 12.2 s (10.6-17.0) | reference host (Linux, WSL2) | 2026-10-16 |
| `scripts/check-affected.sh --no-fetch` (this repository) | pre-push | 15.5 s median on a 28-file range; 0.52 s on one file | reference host (Linux, WSL2) | 2026-10-15 |
| actionlint, per edit (`.github/workflows/*.yml`) | PostToolUse today; moving to pre-commit | 44 ms median (43-47) | reference host (Linux, WSL2) | 2026-10-15 |
| bash-format, per edit (`.sh`, configured) | PostToolUse today | 64 ms median (62-68) | reference host (Linux, WSL2) | 2026-10-15 |
| biome-format, per edit (`.ts`, configured) | PostToolUse today | 62 ms median (60-77) | reference host (Linux, WSL2) | 2026-10-15 |
| markdown-format, per edit (`.md`, configured) | PostToolUse today | 180 ms median (174-186) | reference host (Linux, WSL2) | 2026-10-15 |
| powershell-format, per edit (`.ps1`, configured) | PostToolUse today | 973 ms median (918-1,026) | reference host (Linux, WSL2) | 2026-10-15 |
| ruff-format, per edit (`.py`, configured) | PostToolUse today | 75 ms median (73-83) | reference host (Linux, WSL2) | 2026-10-15 |
| typos-format, per edit (`.md`) | PostToolUse until removed; now pre-commit | 59 ms median (56-63) | reference host (Linux, WSL2) | 2026-10-15 |

The per-edit rows are today's `PostToolUse` rows run from each plugin's `hooks/hooks.json` with a
sample that needs work (hyperfine, 2 warmups, 10 runs; a 15 ms spawn baseline is included). They
are the baseline the git-hook entries and `PostToolBatch` rows replace; each new entry adds its
own row here when it ships.
