# Changelog

All notable changes to the `developer-experience` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.7] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.2.6] - 2026-10-30

### Added

- Four stays-quiet eval cases port the source scenarios Q-build, Q-audit, NM-explain and NM-script ([#9998](https://github.com/melodic-software/claude-code-plugins/issues/9998)): an off-by-one fix in a library method, a text-helper fix with a new test, an explanation of the interactive commit command, and a fix to a build script that ignores a failed build. Each checks that build-cli and audit-tools stay out of an ordinary coding task, with deterministic graders on the files the task changes and on what it must leave alone.

## [0.2.5] - 2026-10-29

### Added

- Eval cases `s2-tracker-comment` and `s5-release-review`, ported from scenarios S2 and S5 on the shared fixtures. `s2-tracker-comment` checks that posting a tracker comment runs the existing `tq item comment` command, creates no source, script or project file and writes or edits none with the Write or Edit tool, and calls neither build-cli nor audit-tools. `s5-release-review` judges whether a review of `bfk release` reports the interactive-only confirmation and the missing `--yes` bypass, with a file:line for each gap. It also checks that the review creates no file, makes no Write or Edit call, and runs no shell command that deletes, moves, edits in place or resets files, including one inside a compound command (#9958).

- Eval cases `s7-act-after-yes` and `n1-missing-conventions-nudge`, ported from scenarios S7 and N1 of the eval scenario sources onto the shared fixtures. S7 resumes a recorded turn 1 that proposed a script cleanup and changed nothing, then the user approves only the test-script consolidation. Its graders check for a call that removes `scripts/test.sh`, that `scripts/run_tests.sh` remains and the `Makefile` calls it, and that the `Makefile` keeps its `seed` and `release` targets. They also check that `scripts/seed_fixtures.py` still reads as scaffolded, and that no edit or write touched a file outside that scope. A last check catches `rm`, `git rm`, `mv` or `unlink` on a protected path, also after `&&`, `;` or a pipe. N1 checks that build-cli's final reply tells the user to run `/developer-experience:setup` when the conventions file is missing. ([#9979](https://github.com/melodic-software/claude-code-plugins/issues/9979))

- Eval cases `t1-setup-init` and `t2-setup-rerun`, ported from setup scenarios T1 and T2 of the eval scenario sources onto the shared tarnquill fixture, bare and converged. T1 grades setup apply with free graders: the conventions reach AGENTS.md and no scaffold AGENTS.md line changes, and in the plugin arm the conventions file exists with its front matter and section markers, names only fixture files, and AGENTS.md gains only the managed block with one pointer line. Two plugin-arm `llm` graders, whose samples are the labeled T1 C2 and C3 sets, check that the conventions name only real commands and keep `tq commit` interactive. T2 grades a re-run that leaves both files byte for byte as seeded, with no `Write`, no `Edit`, and no Bash call that writes or deletes a file, including one inside a compound command. ([#9988](https://github.com/melodic-software/claude-code-plugins/issues/9988))

## [0.2.4] - 2026-10-29

### Added

- Eval cases for scenarios T3 and T4 on the shared fixtures. `t3-setup-interactive-release` runs `/developer-experience:setup apply` on the bare `brackenfold` copy and checks that `AGENTS.md` keeps its lines and gains the pointer line, with judge graders on the conventions file it writes. `t4-check-old-location` runs `/developer-experience:setup check` on the legacy `tarnquill` copy with deterministic graders only: nothing written and the seeded files unchanged, the `.claude/` file reported as an old location, the false `--yes` line reported, and the missing `@AGENTS.md` import printed. ([#9993](https://github.com/melodic-software/claude-code-plugins/issues/9993))

## [0.2.3] - 2026-10-29

### Added

- Eval cases `s1-branch-start-plan` and `s4-migrator-plan`, ported from scenarios S1 and S4 of the eval scenario sources on the converged fixtures. Each grades the plan turn: build-cli fires and makes no Write or Edit call and runs no shell command that writes or deletes a file before the user says yes, and in S4 the plan asks which backup format to use and recommends neither, an `llm` grader whose samples are the labeled S4 item 10 set. ([#9953](https://github.com/melodic-software/claude-code-plugins/issues/9953))

- Eval cases `s3-script-cleanup` and `s6-tool-inventory`, ported from scenarios S3 and S6 of the eval scenario sources onto the shared fixtures in their converged state. Each grades the scenario's answer key, file citations and other judge items with `llm` graders, and its read-only items with free graders: no `Write`, no `Edit`, and no `rm` or `git rm`, including one inside a compound shell command. A further grader records whether `/developer-experience:audit-tools` ran. ([#9966](https://github.com/melodic-software/claude-code-plugins/issues/9966))

## [0.2.2] - 2026-10-29

### Added

- Shared eval fixtures under `evals/fixtures/`: the `tarnquill` (.NET) and `brackenfold` (Python) repositories from the eval scenario sources, and `seed.sh`, which seeds either one in the bare, conventions-only or converged state (or, for `tarnquill`, legacy) into a workspace and commits it on `main`. The fixture case `fx-seed-every-state` seeds all seven states and checks the conventions file each copy's `AGENTS.md` names. ([#9943](https://github.com/melodic-software/claude-code-plugins/issues/9943))

## [0.2.1] - 2026-10-24

### Added

- `/developer-experience:build-cli` CLI contract gains five rules for a control CLI: no inherited handles on a started child, one JSON document on `--json` stdout for a composite command, finding the real app process behind a wrapper pid, rejecting bad flags and ids fast, and naming the override mechanism the app honors. Each carries a source pointer, an as-of date and a recheck trigger. A new eval case checks that a review flags a child started with inherited handles.

## [0.2.0] - 2026-10-20

### Added

- Shared `resolve-convention-home.sh` synced: `--ref` (a 40-hex commit id or `origin/<name>`) reads the pointer and the home as committed, `-` reads the region from stdin, a `declined` line in the region exits 4 so the caller does not ask again, and a root that is `$HOME`, an ancestor of it or outside a git work tree exits 5 (not applicable).

### Changed

- With no `--root`, `resolve-convention-home.sh` reads the git toplevel of `CLAUDE_PROJECT_DIR` (else of the current directory): one home per git root.

### Fixed

- Setup's `pointer-line.sh` no longer stops with an internal error in a repository that declined a convention home (it reports `source: declined`, writes nothing and exits 0) or outside a git work tree (it falls back to `docs/conventions/developer-experience.md`).
- A `CLAUDE.md` symlinked to `AGENTS.md`, or the reverse, no longer prints a `duplicate:` notice.

## [0.1.2] - 2026-10-12

### Changed

- `setup`, `build-cli` and `audit-tools` point at the live Claude Code docs sections they rely on by anchor, each with an as-of date and recheck trigger.

## [0.1.1] - 2026-10-11

### Fixed

- `build-cli`'s CLI contract cites clig.dev's Philosophy "Robustness" section by its live anchor, `#robustness-principle`; the old `#robustness` anchor matched no section.

## [0.1.0] - 2026-10-08

### Added

- `setup`, a user-invoked skill that records a repository's developer tooling conventions as current fact and adds one pointer line to `AGENTS.md`; `check` reports drift and `apply` converges.
- `build-cli`, a skill for building, extending, porting or reviewing a team's command-line tools and scripts against a CLI contract.
- `audit-tools`, a read-only inventory of a repository's scripts, command-line tools, skills, hooks, subagents and MCP configs, with findings.
- `pointer-line.sh`, the helper `setup` uses to check or write its one line in the shared `plugin-conventions` block of `AGENTS.md` without touching any other line.
- A shared copy of the recommendation-basis contract, so each recommendation carries a `Basis:` line or is withheld as an open question.
