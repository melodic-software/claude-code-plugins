# Changelog

All notable changes to the `source-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.2]

### Fixed

- `/pull-request create`'s worktreeinclude sync check no longer reports phantom `CHANGED:` lines
  for `.worktreeinclude` patterns that match no files — an unmatched glob stays a literal string
  in Bash and previously fell through to the changed-file branch; it is now skipped.

## [0.5.1]

### Changed

- References to the renamed `/toolchain:build` skill now invoke `/toolchain:check` (toolchain 0.2.0 breaking rename). Version bumped so existing installs pick up the rewritten prompts.

## [0.5.0]

### Added

- **Exec-bit check in `/source-control:commit`.** Immediately after staging, newly-added files whose
  first line is a shebang (`#!`) are checked against the index and fixed with
  `git update-index --chmod=+x` when staged non-executable. Closes the gap where a new `.sh`/`.py`
  script lands as mode `100644` and is only caught by a CI exec-bit lint lane after the push
  round-trip. Runs after the format-before-push check below (not before), because re-staging a
  formatter's fixes reads the worktree file mode and would otherwise silently undo an
  already-applied `--chmod=+x`.
- **Format-before-push check in `/source-control:commit`.** Before drafting the commit message, the
  skill now checks the consuming repo for an already-configured formatter/linter (`package.json`
  scripts, `biome.json`, a `Makefile` target, `.editorconfig` + `editorconfig-checker`, or an
  equivalent repo-native tool) and runs it against the files staged for that commit, re-staging any
  fixes. Scoped to this commit's paths, not the full index, so it never mutates or blocks on staged
  work outside this commit's scope. Runs only tooling that already exists in the consuming repo;
  skips silently when none is discoverable.

## [0.4.1]

### Fixed

- Require a branch-derived issue to be open before adding `Closes #N`, preserve
  merge-commit branch history when integrating the default branch during PR
  babysitting, and stash a dirty worktree before reusing it for the next task.

## [0.4.0]

### Added

- `/source-control:setup` skill: interviews the repo and writes the tracked
  `.claude/source-control.md` commit-subject / PR-title convention config —
  inferring first from the repo's own `CLAUDE.md`/rules, commit-msg hook, or
  git log history before asking. Offers Conventional Commits (11-type
  vocabulary) as the recommended default, or a custom pattern for orgs that
  don't use Conventional Commits. Re-runnable to reconfigure. Ships evals.

## [0.3.1]

### Changed

- Synced the pull-request verify-gate example to the reorganized taxonomy:
  `/verify-changes` / `/build` are now `/verification:confirm` / `/toolchain:build`.

## [0.3.0]

### Added

- `/resolve-conflicts` skill: intent-first resolution of in-progress merge/rebase/cherry-pick
  conflicts — both sides' history read before any hunk is edited, compose-by-default with
  evidence-gated side-dropping, a post-resolution semantic-conflict sweep (build/tests before
  done), and a hard never-`--abort` discipline. Ships three evals.

## [0.2.0]

### Added

- Readiness security-gate, mixed-actor, and three worktree evals.
