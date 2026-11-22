# Changelog

All notable changes to the `formal-verification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.5] - 2026-11-22

### Changed

- The enforcement-ladder copy is at 3.4.0: the `automated-review` rung writes to the repository's
  review-criteria index, else `CODING_STANDARDS.md`, else a `REVIEW.md` no sync bot owns.

## [0.3.4] - 2026-11-21

### Changed

- the shared prerequisites checker gains a latest-release mode

## [0.3.3] - 2026-11-18

### Changed

- The `specify` skill's forms table says what `check` runs over; the behavior is unchanged.

## [0.3.2] - 2026-11-18

### Changed

- The enforcement ladder copy is 3.3.1: its `compiler-setting` row and its last "Where boundary rules live" entry no longer name a language's compiler options or an architecture-test library ([#16787](https://github.com/melodic-software/claude-code-plugins/issues/16787)).

## [0.3.1] - 2026-11-18

### Fixed

- `/formal-verification:specify refresh` can be followed as written: it reads the tip's SHA right after the fetch instead of relying on `FETCH_HEAD`, unlocks a scratch worktree this session locked before removing it, treats a missing runtime the tool needs like a missing tool (the check is `blocked`, its reading and classification still go in the report), says how to run a `## Run` slash command and resolve `<plugin-root>` when the plugin is not installed, says how a ticket-branch pass treats a folder the ticket does not touch, commits the refreshed verification with a subject that passes the repository's commit convention, reuses the recorded seeded break when the changes added no new behavior, and says the stale-coverage warning stays until the follow-up moves the sync commit.
- A seeded break's `change` in `sync.yaml` also names the model edit that carried it, where the check reads a model.

- `/formal-verification:specify` says what `"$PWD"` stands for when the shell's working directory does not carry between calls, and what `check --default-ref` accepts; `create` says a version or usage command that prints and exits non-zero still shows the tool runs; `refresh` says how to run `check` when the slash command cannot be invoked, where the verify skill lists the names to search a diff for, that step 6's edits are made where the commit goes, that an unchanged `## Run` input lets the earlier run stand, what `<folder>` is in the upkeep branch name, to remove the upkeep worktree after pushing, and that the upkeep commit's subject passes the repository's commit convention.
- The formal-area contract's `## Updating` also lists the names in the code the model reads.

## [0.3.0] - 2026-11-17

### Added

- `/formal-verification:specify refresh` brings each `formal-<area>` check back in line with code changed since its sync commit and ends it `in sync`, `updated`, `bug` or `blocked`. It runs each check unchanged, reads and classifies every covered change, updates the verification from the code in a throwaway worktree, and reruns it with a seeded break. A property changes only on a person's yes; a replayed bug goes to `/bugs:write` and `/work-items:track add`. It commits the verification alone, on a ticket branch or through one upkeep pull request, and an unattended run writes only for a check that ends `in sync` or `updated` with its seeded break caught. `--convert <skill-dir>` turns a verification skill outside the contract into a `formal-<area>` skill, attended only.

### Changed

- The contract check's stale-coverage line now ends `run /formal-verification:specify refresh`, so a pull request that touches a covered path is told which check is stale and what refreshes it.

## [0.2.2] - 2026-11-17

### Changed

- The bundled enforcement ladder is 3.3.0: it adds the `formatter` rung, first after
  `compiler-setting` on the static-analysis tier, for a style rule the repository's recorded
  format command can enforce. No rung moves or is renamed.

## [0.2.1] - 2026-11-17

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.

## [0.2.0] - 2026-11-17

### Added

- `/formal-verification:specify`: bare proposes the promise most worth proving (its harm, tool and the `formal-<area>` folder `create` would write) and writes nothing; `create "<promise>"` chooses the tool with the user, writes the model and the `formal-<area>` skill, and hands off only after a seeded break, made in a throwaway git worktree, is caught; `create --unattended` is a dry run that lists its open questions; `check` runs the contract check. `create` first checks that the repository's project instructions opt in to the enforcement ladder's `formal-verification` rung; without it, it goes on only on an attended yes for that run, and an unattended run reports `blocked: formal verification not opted in`. It names no verification tool and installs none.
- `scripts/check.mjs`, the deterministic contract check: it fails a `formal-<area>` skill on missing or wrong frontmatter, a missing section, a missing or invalid `sync.yaml`, a sync commit that is not an ancestor of `HEAD`, a covered path missing at `HEAD` or a check whose command `## Run` does not give, and warns on stale coverage and on verification skills outside the contract; with `--default-ref` it also fails a sync or seeded-break commit that is not on the default branch, since a squash or rebase merge discards it. It edits nothing.
- The `skills_dir` and `check.on_stale` keys of `docs/conventions/formal-verification.yaml`, and an optional `on_stale` (`warn` or `fail`) on a `sync.yaml` entry.

### Changed

- The bundled prerequisites checker honors an entry's optional `when` (`config_any`: file names, or a file and a pattern its text must match): the SessionStart probe stays silent about the entry unless one of those configs sits in the project directory or above it, and `check` reports it INFO there.

- The shared config cascade copy now exports its `fileState` and `escapes` path guards, so a script that reads other repository files can refuse a symlink or a path outside the checkout the same way. Nothing that already used the cascade changes.

## [0.1.0] - 2026-11-17

### Added

- The `formal-verification` plugin, off by default.
- `/formal-verification:chart` model-checks a TLA+ spec with TLC and writes a Mermaid chart of its states and a report with the shortest path to each broken rule. Its scripts take the jar, Java and bounds as arguments and install nothing.
- `/formal-verification:setup` checks the script runtime, Java, the model checker and the renderer, and on a typed `apply install-model-checker` or `apply install-renderer` downloads the pinned file into the plugin data directory, keeping it only when its checksum matches.
- `reference/formal-skill.md`, the contract for a consumer's `formal-<area>` skill: its sections, one `sync.yaml` entry per check, the view file the chart reads, and where model files and unattended writes may go.
- Version pins and default bounds as keys of the consumer's `docs/conventions/formal-verification.yaml`, and the jar, Java and script-runtime paths as plugin options.
