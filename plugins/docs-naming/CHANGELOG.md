# Changelog

All notable changes to the `docs-naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
