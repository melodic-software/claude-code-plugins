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
  [naming.md](naming.md#location-rules);
- a legacy testing-format map at any other path (`.claude/skills/feature-map/` or wherever the
  person's `feature_map_dir` pointed): its `SKILL.md` index has `Application`, `Launch`, `Driver`,
  `Doctor` and `Features` fields and its feature files sit beside it as `<feature>.md` with a
  `## Traps` section. That path is held to the location rules in naming.md minus the last one (the
  `control-<s>` shape), and to the real-path checks; refused, the outcome is **blocked** with the
  rule it breaks. The person passes this path; refresh reads no testing setting to find it.

Without an argument, take each `.claude/skills/control-*/` directory; with several, an attended pass
asks which and an unattended one refreshes each in turn, one branch per skill. With none, and no
legacy map at `.claude/skills/feature-map/`, the outcome is **blocked**: no control skill exists,
and `/app-control:map create` writes one.

A control skill whose feature files are any flat `features/<id>.md` is due a flat-to-folder
conversion; a legacy map is due a format conversion. Both follow Converting a legacy map.

## 2. Decide whether to run

Run the `check` command from SKILL.md with the control skill directory (or the legacy map's path)
as `--map`. `skip unchanged since the last clean pass` means a clean pass was recorded at HEAD on
this host; `skip no commit within 24h and no state on this host` means no record here and an older
newest commit (`--since <N>h|<N>d` widens it). A line starting `run` means there is work.

A pending conversion runs whatever the line says. Otherwise, on `skip` an unattended pass stops and
reports the line; an attended pass reports it and stops unless the person asked for a pass anyway.
Exit 2 is **blocked**, with the script's stderr line as the blocker.

## 3. Refuse an attended-only skill when unattended

When the pass is unattended and the hub (or a legacy index's driver line) carries `Attended runs
only.`, or names a driver that runs the person's own signed-in browser, the outcome is **blocked**:
a pass with no one present never drives the person's browser or sign-ins. The report says the hub
needs a driving tool that runs inside the run's boundary, and that a person changes it. Never
switch tools on your own. An attended pass may proceed.

## 4. Source wave

Find the base commit: the last commit that touched the control skill directory,
`git log -1 --format=%H -- "<dir>"`. List what changed since:
`git diff --no-ext-diff --no-textconv --name-only <base> HEAD`. With no such commit (an untracked
control skill, the usual state just after `create`) or a legacy map being converted, every feature
counts as changed.

Record `git status --porcelain` from the repository root, then dispatch one subagent per feature
file, in waves no larger than the cap SKILL.md states: start the next wave only when every subagent
of the one before has returned. Tell each subagent to use Read, Grep and Glob only and never edit
or run anything; that limit is an instruction in its prompt, and no agent definition enforces it.
Give each its feature file, the index line's `sources` globs, the changed-file list and these
questions: which parts, entry points, handles, routes or commands the file lists are gone, renamed
or moved in the source; which entry points the source now has that the file does not list; which
gotchas no longer apply; and one drive recipe for the live pass. Every answer cites `file:line`.
Features whose sources did not change still get a subagent: a rename can sit in a shared file.

The answers are candidates; nothing is edited yet. When the last wave has returned, run `git status
--porcelain` again. A difference means a subagent changed the tree: the outcome is **blocked**, the
report names each changed path, and nothing is reverted, written or opened.

## 5. Live pass

Drive every feature once, whatever the source wave found, through `/app-control:drive` invoked with
the Skill tool, in a new temporary `--out` directory outside the checkout, passing `--unattended`
on every call when the pass is unattended and the candidates as hints on where a handle may have
moved. Three invariants hold for the whole pass:

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
| Doc drift | The app works and the files describe it wrongly: a renamed handle, a moved route, a missing or extra entry point, a stale gotcha, a changed step order, a missing prerequisite | A correction to the feature file or hub, in the contract's shape, with the index's entry-point counts and `sources` globs kept true. Ships in the pull request |
| Driver gap | The behavior works but the control skill cannot drive it: a `cli/` command that fails or is missing, a Ready that misses a wedged app | A fix in `cli/` or the hub, documented in `cli/README.md`, then that feature driven again live; it ships only when that re-drive passes, else it goes in the report unwritten. Never a floor loosened |
| Product regression | A behavior the files list is gone, or fails against a healthy app | The entry stays as written: the control skill never records a lost behavior as current. Written up through `/bugs:write` when it is enabled, else in the report with drive's evidence. Kept out of the pull request |
| Not mapped | A user-facing feature the control skill does not list | The report |

Then the outcome:

- Nothing to ship: **clean**. Open nothing, and run the `record` command from SKILL.md. A pass that
  only found regressions or unmapped features is still clean.
- Something to ship: **changed**. An attended pass shows the proposed edits and asks before writing,
  committing or opening anything; declined, they go in the report unwritten. An unattended pass
  goes on. Then:
  1. **Branch.** The branch is `control-skill-upkeep/<skill slug>`, the control skill's directory
     name (`.claude/skills/control-shop` gives `control-skill-upkeep/control-shop`), the only branch
     a pass writes for that skill. When a `feature-map-upkeep/<slug>` branch exists for the same
     map, report it with its open pull request if any; never commit to it, merge it or adopt it.
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
  2. **Write** the edits. Then run the Check steps in SKILL.md on the result; a structural finding
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

## Converting a legacy map

A conversion is doc work and rides the same upkeep pull request as the pass's other edits.

- **Target.** A legacy testing-format map converts into `.claude/skills/control-<app slug>/`, the
  slug from its `Application` name through the slug rule in [naming.md](naming.md#slug-rule). When
  that directory already holds a `SKILL.md`, the outcome is **blocked**: refresh never merges two
  maps; the report names both. A flat `features/<id>.md` converts in place to
  `features/<id>/README.md`.
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
  holding `local.json`, unless they exist. A feature step that sends, signs in or writes, with no
  `cli/` to do it, is a driver gap: that entry point is `not driven: needs a cli/ command`, and the
  report says so.
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
- the features found but not mapped;
- any `feature-map-upkeep/<slug>` branch found, reported and not adopted;
- for a conversion, the old and new paths, and the pointer and setting left to change;
- the branch, the commit and the pull request URL, or why there is none.
