# Refresh

Read before step 1 of `refresh`. SKILL.md holds the two `upkeep-skip.sh` commands and the wave
cap; this page holds the rest of each step.

## Contents

- Outcomes
- What a pass may edit
- 1\. Find the control skill
- 2\. Decide whether to run
- 3\. Refuse an attended-only skill when unattended
- 4\. Source wave
- 5\. Live pass
- 6\. Triage, then act
- Converting a legacy map
- Report

## Outcomes

A pass ends in exactly one:

- **clean**: the control skill matches the app. Nothing is edited or opened, and the pass is
  recorded so the next one skips until HEAD moves.
- **changed**: control skill files were edited, committed to the one upkeep branch for that skill,
  and sent out through at most one pull request.
- **blocked**: the pass could not decide. The report names the blocker and what clears it.

## What a pass may edit

Every file a pass creates, edits or deletes sits inside the control skill's directory: the hub,
`features/`, `shared/`, `config/` and `cli/`. A conversion also moves the legacy map's files out of
their old directory in the same commit (see Converting a legacy map); that directory is the one
exception. Product source, tests, the launch recipe's directory, the instruction file holding the
pointer, `docs/conventions/` and every other path stay untouched, even when the pass finds them
wrong: the finding goes into the report.

A pass never changes `safety` or a credential variable name in `config/defaults.json`. A fix that
needs a floor loosened goes in the report, unwritten: only a person loosens a floor, by committing
it.

## 1. Find the control skill

The path argument, when given, is one of:

- a control skill, `.claude/skills/control-<slug>/`, held to the `--dir` rules in
  [naming.md](naming.md#location-rules) and to its [real-path checks](naming.md#real-paths);
- a legacy testing-format map at any other path (`.claude/skills/feature-map/` or wherever the
  person's `feature_map_dir` pointed): its `SKILL.md` index has `Application`, `Launch`, `Driver`,
  `Doctor` and `Features` fields and its feature files sit beside it as `<feature>.md` with a
  `## Traps` section. That path is held to the location rules in naming.md minus the last one (the
  `control-<s>` shape), and to the real-path checks; refused, the outcome is **blocked** with the
  rule it breaks. A legacy map is converted only when the person passes its path; refresh reads no
  testing setting and looks in no default place to find one.

A feature id in place of a path is one or two `/`-separated segments, each one the
[slug rule](naming.md#slug-rule) leaves unchanged; anything else is **blocked**, naming the rule. It
is composed into a path by you and never reaches a shell. It names the control skill whose
`features/<id>/README.md`, else the legacy `features/<id>.md`, exists (with several, an attended
pass asks which; an unattended one is **blocked**, naming them). An argument naming an existing
directory that holds a `SKILL.md` is a path; any other is a feature id. When that control skill is
due a conversion (below), the outcome is **blocked**: refresh its path first. Steps 4 and 5 then cover that feature only, and a clean outcome skips
the `record` command, since the other features went unchecked.

Without an argument, take each `.claude/skills/control-*/` directory, each held to the same rules
and checks as a given one (a refused directory is skipped and named in the report); with several,
an attended pass asks which and an unattended one refreshes each in turn, one branch per skill (see
Return to the starting branch). With none, the outcome is **blocked**: no control skill exists;
`/app-control:map create` writes one, and `/app-control:map refresh <legacy path>` converts a legacy
testing feature map.

A control skill whose feature files are any flat `features/<id>.md` is due a flat-to-folder
conversion; a legacy map is due a format conversion. Both follow Converting a legacy map.

## 2. Decide whether to run

Run the `check` command from SKILL.md with the control skill directory (or the legacy map's path)
as `--map`. `skip unchanged since the last clean pass` means a clean pass was recorded at HEAD on
this host; `skip no commit within 24h and no state on this host` means no record here and an older
newest commit (`--since <N>h|<N>d` widens it). A line starting `run` means there is work.

A pending conversion, a feature id or a handed-in lesson runs whatever the line says. Otherwise, on
`skip` an unattended pass stops and reports the line; an attended pass reports it and stops unless
the person asked for a pass anyway.
Exit 2 is **blocked**, with the script's stderr line as the blocker.

## 3. Refuse an attended-only skill when unattended

When the pass is unattended and the hub (or a legacy index's driver line) carries `Attended runs
only.`, or names a driver that runs the person's own signed-in browser, the outcome is **blocked**:
a pass with no one present never drives the person's browser or sign-ins. The report says the hub
needs a driving tool that runs inside the run's boundary, and that a person changes it. Never
switch tools on your own. An attended pass may proceed.

## 4. Source wave

**A legacy conversion is written first.** Drive reads only control skills, so before the source
wave of a legacy map's conversion, record `git status --porcelain` from the repository root. When
`git status --porcelain -- "<legacy dir>"` prints any line not starting `??` (a tracked legacy file
with uncommitted changes), the outcome is **blocked** and nothing is written: the person commits or
stashes those changes first. Otherwise an attended pass shows the planned conversion (the upkeep
branch, each legacy file and its new path) and asks; declined, the outcome is **blocked** and
nothing is written. Approved, or unattended, do step 6.1 (branch, same rules), then copy the legacy
directory into a new temporary directory outside the checkout (`mktemp -d`). Then move the legacy
files into `.claude/skills/control-<slug>/` with `git mv` (plain move for an untracked map) and
rewrite them in place per Converting a legacy map, re-running the
[real-path checks](naming.md#real-paths) before each write and listing every path the conversion
creates, moved files' new paths included. Commit nothing yet; the `sources` globs and each entry
point's `driven` mark wait for step 6.2. Both passes then read the converted control skill. The
step-6 ask then covers the pass's other edits. A pass that stops before step 6.3, or whose step-6
edits are declined, undoes the conversion before it ends: it unstages each listed path
(`git reset -q -- <path>`) and deletes it, then each directory the conversion created that is left
empty; unstages the legacy directory (`git reset -q -- "<legacy dir>"`); copies the legacy files
back from the temporary copy; and returns to the branch the pass started on. The report names each file
and says the conversion was undone. Done when `git status --porcelain` prints what it printed before
the pass; only then, or after step 6.3 commits the conversion, is the copy deleted, and until then
the report names its path. Every other pass keeps the order below.

Find the base commit: the last commit that touched the control skill directory,
`git log -1 --format=%H -- "<dir>"`. List what changed since:
`git diff --no-ext-diff --no-textconv --name-only <base> HEAD`. With no such commit (an untracked
control skill, the usual state just after `create`) or a legacy map being converted, every feature
counts as changed.

Record `git status --porcelain` from the repository root, then dispatch one subagent per feature
file, in waves of the cap SKILL.md states, each filled to the cap before the next starts (8 features
run as 6 then 2): start the next wave only when every subagent of the one before has returned. Tell each subagent to use Read, Grep and Glob only and never edit
or run anything; that limit is an instruction in its prompt, and no agent definition enforces it.
Give each its feature file, the index line's `sources` globs (none yet in a conversion), the
changed-file list and these questions: which parts, entry points, handles, routes or commands the file lists are gone, renamed
or moved in the source; which entry points the source now has that the file does not list; which
gotchas no longer apply; and one drive recipe for the live pass. The first subagent also gets the
hub and is asked which of its `## Gotchas` no longer apply. Every answer cites `file:line`.
Features whose sources did not change still get a subagent: a rename can sit in a shared file.

The answers are candidates; nothing is edited yet. When the last wave has returned, run `git status
--porcelain` again. A difference means a subagent changed the tree: the outcome is **blocked**, the
report names each changed path, and nothing is reverted, written or opened.

## 5. Live pass

Drive every feature once (or the one feature a feature id names), whatever the source wave found,
through `/app-control:drive` invoked with the Skill tool, in a new temporary `--out` directory
outside the checkout, passing `--unattended` on every call when the pass is unattended and the
candidates as hints on where a handle may have moved. Three invariants hold for the whole pass:

1. **Ready first.** Run `/app-control:drive ready <slug> --out <dir>` before the first drive, and
   again after any failed drive, before that failure counts against the app.
2. **Clean up each drive.** Run `/app-control:drive cleanup <slug> --out <dir>` when each feature's
   drive finishes; no process or browser session a drive opened survives it. The no-orphan check in
   [prove.md](prove.md#checks-after-the-proof) holds for every launch record the pass leaves.
3. **Evidence survives.** After each cleanup, every evidence path drive reported exists and is not
   empty.

The sign-in rule in [prove.md](prove.md#sign-in-comes-first) holds across the whole pass: one
attempt per account per refresh run, and a failed sign-in stops the live pass.

When the app does not build or start, or Ready still fails, the outcome is **blocked** with drive's
evidence. When drive reports that the hub's driving tool cannot run on this host, the outcome is
**blocked: driver unavailable**, with drive's report: no candidate is written, the report lists
each with its `file:line`, and the tool is not switched.

## 6. Triage, then act

Sort every difference between the control skill and the app:

| Class | What the passes show | Where it goes |
|---|---|---|
| Doc drift | The app works and the files describe it wrongly: a renamed handle, a moved route, a missing or extra entry point, a stale gotcha, a changed step order, a missing prerequisite, a lesson to place (SKILL.md Lessons) | A correction to the feature file or hub, in the contract's shape, with the index's entry-point counts and `sources` globs kept true. Ships in the pull request |
| Driver gap | The behavior works but the control skill cannot drive it: a `cli/` command that fails or is missing, a Ready that misses a wedged app | Attended: after the person agrees, a fix in `cli/` or the hub, documented in `cli/README.md`, then that feature driven again live; it ships only when that re-drive passes, else it goes in the report unwritten. Unattended: the fix goes in the report unwritten and nothing is driven again, since the `cli/` code enforces the safety floors and no one has reviewed the change. Never a floor loosened |
| Product regression | A behavior the files list is gone, or fails against a healthy app | The entry stays as written: the control skill never records a lost behavior as current. Written up through `/bugs:write` when it is enabled, else in the report with drive's evidence. Kept out of the pull request |
| Not mapped | A user-facing feature the control skill does not list | The report |

Then the outcome:

- Nothing to ship: **clean**. Open nothing, and run the `record` command from SKILL.md. A pass that
  only found regressions or unmapped features is still clean.
- A driver gap this pass observed (a `cli/` command that failed or was missing for a step the live
  pass ran) and left unwritten, in an unattended pass or after a failed re-drive: **blocked**, with
  the fix in the report. An entry already marked `not driven` is recorded state, not a gap. Run no `record`, so the next pass checks it again. Other edits from the same
  pass still ship as **changed** describes, and the outcome still reads blocked.
- Something to ship: **changed**. An attended pass shows the proposed edits and asks before writing,
  committing or opening anything; declined, they go in the report unwritten. An unattended pass
  goes on. Then:
  1. **Branch.** A legacy conversion did this before step 4 and stays on that branch. The branch
     is `control-skill-upkeep/control-<slug>`, the control skill's full directory name (`.claude/skills/control-shop` gives `control-skill-upkeep/control-shop`, never
     `control-skill-upkeep/shop`), the only branch a pass writes for that skill. List every local
     and remote `feature-map-upkeep/*` branch (`git branch --list 'feature-map-upkeep/*'` and
     `git branch -r --list '*/feature-map-upkeep/*'`) and report each one by name, with its open
     pull request if any; never check out, commit to, merge or adopt one.
     Create the upkeep branch from the default branch when it does not exist; when it does, merge
     the default branch into it, never a rebase. Before switching, run
     `git ls-files -- "<dir>"` and `git status --porcelain --untracked-files=all`:
     - status prints nothing: switch;
     - `ls-files` prints nothing and every status line is inside the control skill directory (or,
       for a conversion, the legacy map directory): an **untracked** control skill. Its files move
       with the switch and step 3 commits them;
     - otherwise **blocked** before switching, with the edits in the report unwritten. The blocker
       is each status line outside those directories, or the tracked files there holding
       uncommitted changes.

     When git refuses the switch or merge, the outcome is **blocked** with git's stderr line.
     Done when `git branch --show-current` prints the upkeep branch.
  2. **Write** the edits (for a legacy conversion, also the `sources` globs and `driven` marks),
     re-running the [real-path checks](naming.md#real-paths) before each write. Then run the Check steps in SKILL.md on the result; a structural finding
     in a file this pass wrote is fixed before the commit, and one it cannot fix makes the outcome
     **blocked** with the finding.
  3. **Commit** only the control skill's files, staged by path (and for a conversion, the legacy
     directory's removal): the edited files and, for an untracked skill, every file under it, in
     one commit. Done when `git status --porcelain -- "<dir>"` prints nothing.
  4. **Pull request.** With the source-control plugin enabled, look for an open pull request from
     the branch with `/source-control:pull-request list --head "<branch>"`. One exists: push the
     branch, which updates it. None: open one through `/source-control:pull-request create`, in the
     open state that skill resolves. Without the plugin, or when the list call fails, leave the
     commit on the branch and report that a pull request still needs checking or opening, with any
     error. Done when the report holds the pull request URL or the reason there is none.

### Return to the starting branch

A pass over several control skills records `git branch --show-current` before the first one. After
each control skill's step 6, whatever its outcome, it switches back to that branch before the next
skill's step 1, so no skill is refreshed on another skill's upkeep branch. Done when `git branch
--show-current` prints the starting branch.

## Converting a legacy map

A conversion is doc work and rides the same upkeep pull request as the pass's other edits. A
legacy map's conversion is written before step 4 (see there); a flat one's at step 6.2.

- **Target.** A legacy testing-format map converts into `.claude/skills/control-<app slug>/`, the
  slug from its `Application` name (only the part before any `, built from` clause) through the
  slug rule in [naming.md](naming.md#slug-rule). When that directory already holds a `SKILL.md`,
  the outcome is **blocked**: refresh never merges two maps; the report names both. A flat
  `features/<id>.md` converts in place to `features/<id>/README.md`, with its hub index line
  updated to the new path.
- **Hub.** `Application` becomes the App line, `Driver` the driving tool (with `Attended runs
  only.` when it was there), `Launch` the `## Launch` pointer, `Doctor` the `## Ready` command
  (keeping `build: not exposed`), and `Features` the index in the contract's line form, with the
  `sources` globs the source wave found. `## Capture` names only what the repository shows, and
  `## Cleanup` stops only what a run started.
- **Feature files.** Each takes the contract's six sections: `Parts` and `Drive` carry over,
  `Traps` becomes `Gotchas`, `Sub-features` is `none` unless the old file pointed at another
  feature, `Reset` takes the starting data `Drive` named (a flat control-skill file's `## States`
  goes there too), and each entry point ends `driven` or `not driven: <reason>` from the live pass.
- **Config.** Write `config/defaults.json` with every floor at its safe value and `config/.gitignore`
  holding `local.json`, unless they exist. A feature step the contract says needs `cli/` (it sends,
  signs in, or writes to an environment or external system), with no `cli/` to do it, is a driver
  gap: that entry point is `not driven: needs a cli/ command`, and the report says so.
- **Move.** Move every legacy file with `git mv` (plain move for an untracked map) in the same
  commit, so no copy stays behind at the old path. The pointer in the instruction file and any
  `feature_map_dir` setting still name the old path: report both for a person to change.

## Report

- the outcome and, for blocked, the blocker and what clears it (changed paths, drive's report, every
  unwritten candidate with its `file:line`);
- the skip line from step 2, or why a conversion ran past it;
- the driving tool and the hub line naming it;
- each edit, by triage class, with the `file:line` or drive evidence behind it;
- each regression and whether it went to `/bugs:write`;
- each lesson and the Gotchas it went to, or that it is left for `/corrections:codify`;
- the features found but not mapped;
- each `feature-map-upkeep/*` branch found, local or remote, by name, and not adopted;
- for a conversion, the old and new paths, whether a stopped pass undid the conversion, and the pointer and setting
  left to change;
- the branch, the commit and the pull request URL, or why there is none.
