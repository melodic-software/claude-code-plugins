# Changelog

All notable changes to the `docs-naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0] - 2026-10-25

### Changed

- The bundled `generated` default is now empty. It named a regenerator inside the architecture plugin's skill folder, a path only this marketplace's own checkout has, so in any other repository the entry could not run. Declare generated files in the team layer, `.claude/docs-naming.json`.
- In a repository whose team layer declares no `generated` entry, `docs/architecture/landscape.json` is no longer treated as generated. Before, a rename with a site in it stopped before anything moved, because its regenerator resolved to nothing, and `--regenerate-only` failed. Now the sweep and the realign edit its references like any other file's. To keep it regenerated instead of edited, declare it in the team layer with your own regenerate command.

## [0.3.6] - 2026-10-25

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#9684): `detect.version` accepts an exclusive `below` bound; no other change to this plugin.

## [0.3.5] - 2026-10-22

### Changed

- **`/docs-naming:generate-file-name-gate` can now be invoked by the model** ([#8978](https://github.com/melodic-software/claude-code-plugins/issues/8978)). Before, `disable-model-invocation: true` kept it user-typed only. It only emits new files, refuses to overwrite without `--force` and commits nothing, so the invocation-mode grade (#7974) flipped it to `false`.

## [0.3.4] - 2026-10-20

### Fixed

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`.

## [0.3.3] - 2026-10-16

### Fixed

- `lib/check-retirements.sh` finds and cleans a `.git/` leftover, such as a retired git hook,
  when run from a linked worktree: such a path resolves under `git rev-parse --git-common-dir`.

## [0.3.2] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.3.1] - 2026-10-13

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5.** A version or `system-lib` probe that resolves a secret or calls a network API, such as `firecrawl --status` behind a key-injecting wrapper, no longer false-fails on a slow run. A fast probe is unaffected; a hung one now costs at most 20 seconds per entry. No change to this plugin's own entries.

### Fixed

- `/docs-naming:generate-file-name-gate`, its emitted rule and checker templates, and the README no longer state when a path-scoped rule loads, a claim that had drifted from the live memory docs. They now give our own reason the gate is the deliverable (a rule only guides Claude in its session, blocks nothing, and never runs in CI), and the skill points at the live section with an as-of date and recheck trigger.

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

## [0.3.0] - 2026-10-11

### Added

- A `roots` entry may be an object, `{"path", "extensions", "exempt_paths"}`, that limits a root to some extensions (matched in any case) and exempts paths inside it from the basename rule unless another root claims them. The audit inventory, the emitted gate, its rule file, and `setup check` all read it. A string root is now read as a git glob, `<root>/**`, as the audit already read it, so the gate and the audit agree on a directory root and a string root naming a single file claims nothing.

### Changed

- The emitted gate folds paths for the case-collision check with one `tr` over the whole list instead of one per path, so a root holding thousands of files stays fast.
- The rule file's `paths:` globs match a root's extensions in any case, as the gate does, and a root limited to an extension outside the built-in probe names still gets an emitted suite.

### Security

- `generate-file-name-gate` refuses a `regex` or `rule` that carries a newline. Both land on comment lines of the emitted checker, where a newline would end the comment and run the rest as shell on every CI run. It also refuses a root path or root exempt path that is absolute or has a `..` segment, which would otherwise make the emitted gate judge nothing and report a clean tree. The audit inventory refuses the same roots and fails when `git ls-files` refuses a pathspec, and `setup check` reports them as a key-shape FAIL.

## [0.2.7] - 2026-10-04

### Changed

- The README and `realign-file-names` say a renamed file in a versioned unit may need a changelog fragment, where the project releases from fragments, instead of a version bump and changelog entry.

## [0.2.6] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.2.5] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.2.4] - 2026-10-03

### Changed

- `scripts/allowed-tools-pairing.test.sh` declares the files it reads without naming them in a `# test-scope:` header, so CI's test selection runs it when one of them changes. Nothing the plugin runs changed.

## [0.2.3] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.2.2] - 2026-10-02

### Changed

- **Shared `check-retirements.sh`, `config-root.sh` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's lib.**
  Each is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copies.

## [0.2.1] - 2026-10-03

### Changed

- The rename executor's test suite runs in two halves when `APPLY_RENAME_TEST_SHARD` is `1` or `2`, and runs whole when it is unset. It refuses to start if a case group is in neither half. The four cases that edit the tree before auditing now share one pre-audited fixture, so the suite runs the audit three times instead of six. Every assertion is unchanged. No behavior changes.

## [0.2.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5841](https://github.com/melodic-software/claude-code-plugins/issues/5841)).

## [0.1.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.1.3] - 2026-10-02

### Fixed

- The `setup` `argument-hint` uses Claude Code's official bracket notation: it leads with its check
  action and keeps alternatives inside brackets with an unspaced `|`.

## [0.1.2] - 2026-10-01

### Changed

- References to the `claude-config`, `claude-memory` and `claude-ops` plugins now use their new
  names, `harness-config`, `harness-memory` and `harness-ops`.

## [0.1.1] - 2026-10-01

### Changed

- Removed `reference/topic-docs.md` and its binding to the repository's topic-docs convention, which no longer exists. The audit's findings artifact lives in the memory slice, and the bundled config no longer exempts `docs/topics`.

## [0.1.0]

### Added

- **File-name skills.** `setup`, `audit-file-names`, `realign-file-names` and `generate-file-name-gate`
  moved here from the `docs-hygiene` plugin, with their scripts, templates, evals and reference docs.
- **Config files renamed.** The team layer is `.claude/docs-naming.json` and the personal overlay is
  `.claude/docs-naming.local.json`, with the schema unchanged. The old `.claude/docs-hygiene.json` and
  `.claude/docs-hygiene.local.json` are still read for one release with a warning, and `setup apply`
  refuses to write the team layer while the old name stands.
- **Memory directory and artifact type renamed** to `docs-naming`. A rename plan in flight under the
  old name needs a re-audit with `audit-file-names`.
