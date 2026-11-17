# Changelog

All notable changes to the `formal-verification` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
