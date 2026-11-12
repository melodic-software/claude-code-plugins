# Changelog

All notable changes to the `docs-naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.7.13] - 2026-11-12

### Changed

- Internal restructuring, no behavior change.

## [0.7.12] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.7.11] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [0.7.10] - 2026-11-11

### Fixed

- The `audit-file-names` and `realign-file-names` skills no longer say the Bash tool returns a command's complete
  output into context. The rule stands (the pipe is the bound, so it belongs in the command); the reason now points at the Output
  limits section of the Claude Code tools reference for what a result returns inline.

## [0.7.9] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [0.7.8] - 2026-11-09

### Changed

- Internal simplification, no behavior change.

## [0.7.7] - 2026-11-09

### Changed

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

## [0.7.6] - 2026-11-09

### Changed

- Internal simplification, no behavior change.

## [0.7.5] - 2026-11-09

### Changed

- Simplified the shared resolve-convention-home.sh, resolve-convention-pattern.sh and rewrite-guard.sh copies; behavior is unchanged.

## [0.7.4] - 2026-11-08

### Changed

- Shared `check-retirements.sh` synced where this plugin carries it ([#14251](https://github.com/melodic-software/claude-code-plugins/issues/14251)): it accepts a `block` record kind, which cleans one YAML key and its indented value instead of the whole file. No other change to this plugin.

## [0.7.3] - 2026-11-07

### Changed

- The generate-file-name-gate, audit-file-names, realign-file-names and setup `evals.json` files are retired
  into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
  Twelve new cases on a shared fixture, `evals/fixtures/fn-repo.sh`:
  `audit-plans-renames-tiers-frozen` (the three scripts write the plan, the form table comes first and frozen
  sites are counted),
  `audit-case-collision-refuses` (a case-only collision writes no plan),
  `audit-review-sites-escalated` (six ambiguous `review` sites are shown, not applied),
  `realign-applies-one-id` (one id is presented, applied and swept),
  `realign-refuses-blanket-yes` (a blanket yes is refused with its reason),
  `realign-moved-file-blocks` (a moved file blocks with re-audit as the remedy and no search for it),
  `realign-frozen-and-review-untouched` (released and `review` sites stay as written),
  `setup-check-layers-and-retired-team` (the table as printed and `docs-naming-r001` as INFO),
  `setup-check-malformed-layer-fails` (a malformed layer fails with exit 1),
  `setup-apply-defaults-verifies` (apply through the script, then re-check),
  `setup-personal-tier-not-narrowed` (a personal layer cannot narrow the `tiers` key) and
  `setup-apply-retired-personal-override` (`docs-naming-r002` as INFO and no personal write).
  The gate's legacy cases 1 and 2 were already covered by `gate-emits-and-names-unwired` and
  `gate-refuses-overwrite`. Gate case 3 is held: its `--rule` write under the workspace `.claude/` is denied
  in an eval run.

## [0.7.2] - 2026-11-05

### Fixed

- `lib/check-retirements.sh` skips `kind: file` records, and refuses `--clean` of one, when the root is `$HOME` or not inside a git work tree ([#13504](https://github.com/melodic-software/claude-code-plugins/issues/13504)). There a `.claude/<name>.json` path is the live user-global layer, not a retired team file; stderr reports `<id>: skipped: root is not a repository`.

## [0.7.1] - 2026-11-04

### Changed

- Prose uses the vocabulary the planning chain settled on (scope, fallback chain, personal override, the Brief), and names the file or setting it means.

## [0.7.0] - 2026-11-04

### Changed

- **The config cascade's personal layer is called the personal override.** `scripts/resolve-config.sh` names it `personal-override` where it printed `overlay`: in the `paths` and `layers` output, the `!inert:` lines, the `_layer` stamp on a tier from `docs-naming.local.yaml`, and its error messages. `/docs-naming:setup check` prints the rows `layer personal-override`, `old personal override file` and `personal override ignored`. The setup skill, README, `reference/config.md` and `retirements.yaml` use the same name. Which file is read and how layers merge are unchanged ([#13190](https://github.com/melodic-software/claude-code-plugins/issues/13190)).

## [0.6.1] - 2026-11-04

### Changed

- Shared config-cascade library synced: comments now call the personal layer the personal override (#13187). No behavior or printed text changed.

## [0.6.0] - 2026-11-04

### Removed

- The one-release reads of the pre-YAML team and overlay files, added in 0.5.0. `scripts/resolve-config.sh` reads the team layer only from `docs-naming.yaml` and the overlay only from `docs-naming.local.yaml` under the convention home, never from `.claude/docs-naming.json`, `.claude/docs-naming.local.json`, or their retired `docs-hygiene` names, and `paths` no longer reports a `deprecated` state. Retirement records `docs-naming-r001` and `docs-naming-r002` are demoted to `report-only`. `/docs-naming:setup check` prints a WARN row for each old team or overlay file it finds. While the team YAML is absent, the first `/docs-naming:setup apply` still copies the old team file's keys into it and leaves that file in place. A repository that keeps its settings in an old file runs that write (or moves overlay keys by hand), then deletes the old file. The user-global `~/.claude/docs-naming.json` is still read ([#9737](https://github.com/melodic-software/claude-code-plugins/issues/9737), [#12287](https://github.com/melodic-software/claude-code-plugins/issues/12287)).

## [0.5.6] - 2026-11-02

### Changed

- Hook notices name the bundled checker command; `check` is optional (#12485).

## [0.5.5] - 2026-11-02

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.

## [0.5.4] - 2026-11-01

### Added

- Frozen trigger-probe sets for the three model-invoked skills (`generate-file-name-gate`, `audit-file-names`, `realign-file-names`), 18 probes each, for measuring description auto-invocation in a later round.

## [0.5.3] - 2026-10-31

### Fixed

- The convention-home resolver refuses a pointer that names `.git` or a path inside it, and a
  working-tree home reached through a symlink: both exit 3.

## [0.5.2] - 2026-10-30

### Changed

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.5.1] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.5.0] - 2026-10-30

### Added

- The team layer now lives in `docs/conventions/docs-naming.yaml` (under the repository's convention home) and the personal overlay in `docs/conventions/docs-naming.local.yaml`, validated by the new `schemas/docs-naming.schema.json` ([#9731](https://github.com/melodic-software/claude-code-plugins/issues/9731)). The keys are top-level keys of the file, with no `schema` or `file_names` wrapper.
- `scripts/resolve-config.sh paths` reports a layer read from the pre-YAML location as `deprecated`, and `/docs-naming:setup check` shows it as a WARN row.

### Changed

- `scripts/resolve-config.sh` reads the YAML first. For one release a team or overlay layer whose YAML is absent is read from the JSON file under `.claude/` it used to live in; the YAML wins whenever it exists and the two are never merged. The user-global layer stays a JSON file.
- `/docs-naming:setup apply` writes the YAML, seeds it on the first write from the JSON team layer the resolver reads in its place (the pre-YAML file, else the retired `docs-hygiene` one, which apply no longer refuses) so a fresh file never shadows those settings, and keeps the comment block at the top of an existing file. The retirement records and `/docs-naming:setup check` now point a retired file's settings at the YAML. `/docs-naming:setup check` follows the layer files the resolver names, and recommends the overlay gitignore line beside the overlay.
- A broken convention-home pointer (malformed, duplicate or dangling) now stops `scripts/resolve-config.sh` and `/docs-naming:setup apply` with the resolver's message instead of falling back to `docs/conventions`, and a top-level YAML key with no value (`regex:`) is an error naming its line instead of a silently undeclared key.
- `reference/config.md`, the README and the setup skill describe the YAML layers and the one-release fallback.

## [0.4.2] - 2026-10-29

### Fixed

- **The docs-naming scripts no longer pipe into an early-exit grep** ([#11034](https://github.com/melodic-software/claude-code-plugins/issues/11034)). `setup-check.sh`, `inventory.sh`, `emit-gate.sh` and `lib/check-retirements.sh` match names against the casing regex, the folded directory list and the retirement fields with a here-string instead of `printf | grep -q`, so under `set -o pipefail` a match can no longer read as a miss when grep exits before printf finishes writing.

## [0.4.1] - 2026-10-27

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.

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
