# code-tidying

A Claude Code plugin for **structure-only** codebase improvement, applying Kent
Beck's *Tidy First?* discipline agentically: small named tidyings, separated
from behavioral changes by commit and by PR, under a research-backed scope
budget (≤200 LOC / ≤8 files target; ≤400 / ≤15 hard cap).

Three skills, one capability:

- **`/code-tidying:tidy`** — proactively hunts a rotated, glob-scoped *lane* of
  the codebase for safe structural improvements (Beck's 15 tidyings + a Fowler
  subset + prose tidyings), applies scope-budgeted edits, and ships one tight
  structure-only PR. Overflow is filed as deferred work items, never silently
  dropped.
- **`/code-tidying:batch-simplify`** — sweeps files changed in a time window
  (`48h` default, `7d`, ...) or on the current branch through grouped,
  dependency-ordered simplification waves, with per-group verification and a
  never-drop deferred-items contract. Use it when you forgot to run
  `/simplify` after each task.
- **`/code-tidying:setup`** — interviews the repo and scaffolds tracked
  `.claude/tidy-lanes/<lane>.md` project lane files from the bundled templates,
  so `tidy` resolves project-specific scope globs deterministically instead of
  falling back to the generic bundled lanes. Re-runnable to add or retune lanes.

Neither `tidy` nor `batch-simplify` is `/simplify` itself: `/simplify` refines the diff you just
wrote; `batch-simplify` catches up on a window of them; `tidy` hunts drift no
one has filed yet.

## Lanes — the extension surface

`tidy` operates on lanes. Bundled lanes cover surfaces that look the same in
most repos (`shell-tooling`, `docs-prose`); your project defines its own lanes
by dropping files into **`.claude/tidy-lanes/<lane>.md`**, which take
precedence over bundled lanes of the same name. Copy the closest scaffold from
the plugin's `skills/tidy/templates/` (dependency-root, host-wiring, apps,
polyglot-services patterns) and fill in your scope globs, watch-for patterns,
exclusions, and verification commands.

## Safety model

- **Structure-only, always.** A "tidying" that breaks a test was secretly
  behavioral — it gets backed out, not shipped.
- **Hard/soft exclusions** gate every run: agent and CI configuration, hook
  chains, and lint configs are never touched; unverifiable areas (browser UI,
  auth flows, DB migrations) are deferred, not edited. Your project's own
  `CLAUDE.md` / rules extend both lists.
- **Backlog throttle**: ≥3 open `chore/tidy-*` PRs stops the run instead of
  piling on (bundled `open-pr-count.sh`, network access via your own `gh`
  auth).
- **No auto-merge.** Tidy PRs are always merged by a human.

## Works in any repo

- Self-contained: taxonomy, scope-budget research, exclusion lists, lane
  templates, and the throttle script all ship inside the plugin under
  `${CLAUDE_PLUGIN_ROOT}`.
- Graceful degrade: if the `discovery` plugin is installed, explore/research
  phases use `/discovery:explore` + `/discovery:research`; if `work-items` is
  installed, deferrals file through `/work-items:track add`; if
  `pr-review-toolkit` is installed, batch-simplify uses its `code-simplifier`
  agent. Absent any of them, the skills fall back to inline
  exploration/research, `gh issue create`, and general-purpose agents.
- Reads your conventions, assumes none: canonical build/test/lint commands,
  protected paths, and unverifiable areas come from your own project context.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install code-tidying@melodic-software
```

## Configuration

No `userConfig`. Project-specific behavior routes through
`.claude/tidy-lanes/` lane files and your project's own `CLAUDE.md` /
`.claude/rules` (protected paths, verification commands). Run
**`/code-tidying:setup`** to interview your repo and scaffold those lane files
from the bundled templates — it is idempotent and safe to re-run to add or
retune lanes.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
