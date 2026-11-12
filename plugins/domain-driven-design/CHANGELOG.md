# Changelog

All notable changes to the `domain-driven-design` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.4] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.9.3] - 2026-11-11

### Changed

- The README options reference lists its upstream documentation as pointers only, with no as-of date or recheck trigger.

## [0.9.2] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [0.9.1] - 2026-11-11

### Fixed

- `ubiquitous-language` `locate` step 1: a declared glossary path wins only when it resolves inside
  the current repository. A declared path outside it is ignored for discovery and never created or
  written.

## [0.9.0] - 2026-11-11

### Added

- `audit` step 5: code names that look like an existing term's concept but are neither the term nor its `Avoid:` words are reported with a count and `file:line`, each proposed as a new `Avoid:` word through `curate`. Duplicated logic stays with `/code-metrics:audit-duplication`.
- `curate` removal reports every surviving reference to a removed term (bold mentions in other entries, the glossary index, docs), and its report names where each removed term's meaning went.
- `curate` names `CODEOWNERS` on the glossary path as the route for a team that wants a domain owner to review glossary changes; there is no reviewer setting.
- New eval case `cl-audit-unrecorded-synonym`, and three invocation probes for codebase terminology, a named glossary file and the domain model.

### Changed

- Glossary contract: an `Avoid:` line holds only other names for the same concept; a word with its own meaning gets its own entry or stays off. `audit` reports a hit on such a word as a candidate entry, not drift.
- `audit`'s Implementation group also names a constant or setting that lives in code, and its cut-sentence suggestion adds operating detail to user docs or command help.
- Description adds 'tidy our codebase terminology' and 'the terms in our domain model' as triggers.

## [0.8.1] - 2026-11-11

### Changed

- `ubiquitous-language` points at the live saved-value section for where settings are filled in
  instead of restating it. No behavior change.

## [0.8.0] - 2026-11-10

### Added

- Glossary contract: a term is used bare inside its own bounded context and qualified by its context wherever contexts meet (the glossary index, integration code, cross-context docs).
- Glossary contract: a concept tenants rename on their own screens keeps one model term, recorded as `Shown to users as: configurable per tenant`; tenant words are configuration, never synonyms or `Avoid:` words.
- `curate` weighs candidate terms in order: domain experts, then the code's existing usage, then published domain standards as inputs, never authority, researched through `/discovery:research` when none is known. Users' differing words go on `Shown to users as:`.

## [0.7.0] - 2026-11-10

### Added

- `audit` proposes entries to prune, grouped by kind with a one-line reason: an implementation entry (a table, column, component, file or route), a term too general to carry project meaning, a canonical term no longer used, and a phrase one existing term already covers. A plain request such as "prune the glossary" or "the glossary feels bloated" routes to `audit`, which stays read-only.
- `curate` removes or merges entries a person accepted, one group at a time and only on a yes; unattended it writes nothing.
- Glossary contract: one counting method for every count `audit` and `curate` give (identifiers split at camelCase, PascalCase and snake_case boundaries, whole words, case-insensitive, with the number of files), and a rule that ADRs and docs use a term but never redefine it.

### Changed

- `curate`'s hand-off to `/docs-hygiene:rename-references` groups hits by layer: accepted ADR text takes the new term while ADR file names and numbers stay unchanged, and a stored database value is a decision, either a phased expand, migrate and contract migration or an explicit mapping, recorded with `/architecture:record-decision`.

## [0.6.0] - 2026-11-10

### Added

- Glossary contract: an optional `Actions:` line under an entity records the verb chosen for an operation on it when another verb was contested, the rejected one in parentheses (`Actions: submit (Avoid: raise)`). `lookup` returns it, resolves a rejected verb to its entry and tells its caller the verb is rejected only for that operation on that entity; `curate` and `audit` search for rejected verbs where they name that operation on that entity.

### Changed

- Glossary admission: everyday words used in their ordinary sense stay out; a term earns an entry only when it removes ambiguity in its context (a project-specific meaning, a clash between meanings, or a rejected synonym). `seed` leaves such words out and `audit` flags entries that do not pass.

## [0.5.1] - 2026-11-10

### Changed

- The glossary contract keeps business rules out of entries: an entry says what a concept is, the rule lives in code and a test that names it, and the rule's reason goes in an ADR when it passes `/architecture:record-decision`'s admission test. `audit` reports a rule found in a definition.
- `/domain-driven-design:ubiquitous-language` names `/architecture:record-decision` for decisions about why the system is built a certain way.

## [0.5.0] - 2026-11-10

### Changed

- **Breaking:** the `curate-language` skill is renamed `/domain-driven-design:ubiquitous-language`. Invoke the new name; the settings `glossary_file` and `glossary_map_file` and their file `docs/conventions/domain-driven-design.yaml` are unchanged.
- The skill now has five actions: `locate` (find the glossary, searching the whole repository so a `docs/glossary.md` is found), `lookup` (the read-only path other skills use), `seed` (propose a first glossary from code and docs, a person accepting each term), `curate` (the previous maintenance workflow) and `audit` (check entries and find rejected words in code, copy and error messages, report only).
- Glossary contract: a header sentence says what `Avoid:` means; an entity's states are listed under it, with a state getting its own entry only when it is used as a noun with rules of its own; an optional `Shown to users as:` line records deliberate screen wording. The map file is called the glossary index. Missing bounded contexts route to `/event-storming:simulation`.
- After a glossary change, rejected words found in code names are handed to `/docs-hygiene:rename-references` as their own change, and those in user-facing copy and error messages are reported, never rewritten.

## [0.4.22] - 2026-11-09

### Changed

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

## [0.4.21] - 2026-11-09

### Changed

- Internal simplification, no behavior change.

## [0.4.20] - 2026-11-09

### Changed

- Simplified the shared resolve-convention-home.sh, resolve-convention-pattern.sh and rewrite-guard.sh copies; behavior is unchanged.

## [0.4.19] - 2026-11-05

### Changed

- `/domain-driven-design:curate-language`: the fallback glossary shape groups terms under subheadings when they fall into clear clusters; a small or uniform set stays one list.

## [0.4.18] - 2026-11-04

### Changed

- The README, the schema, the glossary contract and the glossary-settings script's comments and
  test name now call the config cascade's gitignored `domain-driven-design.local.yaml` layer the
  personal override, the marketplace's name for it (#13192). Behavior is unchanged.

## [0.4.17] - 2026-11-04

### Changed

- Shared config-cascade library synced: comments now call the personal layer the personal override (#13187). No behavior or printed text changed.

## [0.4.16] - 2026-11-04

### Changed

- Shared `config-cascade.mjs` synced where this plugin carries it ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)): it exports the scan that finds a `yaml config` block in a team Markdown file, returning the block's body; resolution is unchanged and there is no other change to this plugin.

## [0.4.15] - 2026-11-03

### Changed

- The legacy `skills/curate-language/evals/evals.json` is converted and removed: its five scenarios the `cl-*` suite already covers are dropped, and its other three become `evals/curate-language-*` cases beside it (attended glossary proposal, no empty or fixed-name file, passive lookup) ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- `/domain-driven-design:curate-language` records a name the resolution rules out ("never the X") as a rejected synonym in the file's convention, not inside the definition.

## [0.4.14] - 2026-11-03

### Changed

- the shared config-cascade library gains `readLayers`

  It returns each layer's own accepted values, unmerged, for the shared
  medium resolver. `resolve()`, which this plugin calls, is unchanged.

## [0.4.13] - 2026-11-02

### Changed

- The `curate-language` description is back to its earlier text. The shorter one shipped on an eval that a negative control showed cannot tell it from a one-line generic description, so the cut was never measured.

## [0.4.12] - 2026-11-01

### Changed

- `curate-language` has a shorter description (587 to 506 characters) with the same triggers, branches and exclusions. Measured with no loss of triggering on Opus 5.5 and Sonnet 5.5.

## [0.4.11] - 2026-11-01

### Changed

- The config cascade skips the setup writer's top-level `written_against` and `provenance` keys, so
  neither reaches `values`, a layer's errors or a userConfig name.

## [0.4.10] - 2026-10-31

### Fixed

- The convention-home resolver refuses a pointer that names `.git` or a path inside it, and a
  working-tree home reached through a symlink: both exit 3.

## [0.4.9] - 2026-10-30

### Changed

- The generated plugin-options block in this plugin's docs now links `docs/contracts/<name>/` instead of the old `docs/conventions/<name>/` stub.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.4.8] - 2026-10-30

### Changed

- `yaml-subset.mjs` gains a `source` option that keeps each scalar as its source text. Default parsing is unchanged (#10131).

## [0.4.7] - 2026-10-29

### Changed

- The generated README "How to set these" block names `claude plugin configure <plugin>@<marketplace> --values-stdin` as the preferred headless route, per the plugin-reconfiguration convention, and keeps the `claude plugin install --config` rerun only as its fallback.

## [0.4.6] - 2026-10-29

### Changed

- The config reader now refuses a plain YAML value holding a colon and a space (such as `label: needs: triage`) and a plain key holding whitespace, `$` or `.` (such as `$schema: x` or `a.b: c`), naming the line. One such line now makes the whole file invalid, where the value used to be read as text or the key reported on its own. Quote the value or key to keep it.

## [0.4.5] - 2026-10-28

### Fixed

- The shared config resolver now tags each layer error with the key it names (`error_keys`, null for a
  file-level error), so a reader can tell a key-level error from a whole-file one.

## [0.4.4] - 2026-10-27

### Changed

- The README's generated "How to set these" block no longer restates Claude Code CLI and settings behavior as fact. Each upstream specific is now a link to the docs section that owns it (`/plugin` in a session, what an uninstall deletes and keeps, `pluginConfigs`), and what this repository measured stays in the plugin-reconfiguration convention.

## [0.4.3] - 2026-10-27

### Security

- `glossary-settings.mjs` runs `git` from the plugin's own directory, so on Windows, where Node looks for a bare command in the working directory before `PATH`, a `git.exe` or `git.com` committed to the user's repository is never run.

## [0.4.2] - 2026-10-26

### Fixed

- `scripts/lib/yaml-subset.mjs` reads an empty sequence item (`-` alone) as `null` when the next line is another item at the same indent, instead of nesting the following items under it.
- A quoted key may hold a doubled `''` in single quotes or a `\"` escape in double quotes; such a key no longer fails with `expected a mapping entry`.

## [0.4.1] - 2026-10-26

### Changed

- The bundled config cascade (`scripts/lib/config-cascade.mjs`) now enforces a schema `maximum`, as it already did `minimum`.

## [0.4.0] - 2026-10-20

### Added

- **Glossary file-name settings.** `glossary_file` (default `GLOSSARY.md`) and `glossary_map_file` (default `GLOSSARY-MAP.md`) resolve through the config cascade: the plugin default, `userConfig`, the team file `docs/conventions/domain-driven-design.yaml` and the personal overlay, validated by `schemas/domain-driven-design.schema.json`. `scripts/glossary-settings.mjs` reports the layer that supplied each name and drops a layer whose value is a path rather than a file name.

### Changed

- **`/domain-driven-design:curate-language` proposes a glossary layout when the repository has none.** It proposes one `glossary_file` per bounded context, opening with a short description of the context, and one `glossary_map_file` at the repository root once more than one context exists. An attended run asks before writing; an unattended run still writes nothing and reports the missing convention. The skill also states that framework and tooling nouns belong in the architecture docs, not the glossary.

## [0.3.6] - 2026-10-20

### Changed

- `/domain-driven-design:curate-language` gains a `## Next` section naming `/planning:plan`.

## [0.3.5] - 2026-10-04

### Changed

- The README's `curate-language` row now says the skill sharpens definitions to state what each term is, matching the manifest description.

## [0.3.4] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.

## [0.3.3]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** This changelog and `skills/curate-language/SKILL.md` were rewritten. Wording only, with no change to any glossary rule or routing. All four trigger phrases are byte-identical. The released sections corrected in place are 0.3.0, 0.2.0, and 0.1.0: their wording changed, their facts did not.
- **`curate-language`'s summary takes the period form, and the cheat sheet is regenerated with it.** That summary renders into `docs/SKILL-CHEAT-SHEET.md`, so the source and the generated sheet move together. A colon was not an option: `summary:` is an unquoted YAML scalar, and a colon followed by a space would break the parse.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md` and every `skills/*/SKILL.md`.

## [0.3.2]

### Changed

- **curate-language:** the invocation section states the current relationship with the planning
  plugin (invoke when installed) instead of a manifest dependency that no longer exists, and drops
  the unreachable "when unavailable" guidance addressed to other plugins' authors; the body defers
  the convention-resolution ladder to `context/glossary-contract.md` instead of carrying a shorter
  divergent copy, and the read gate covers convention resolution as well as writes. The README's
  install note says the same.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.3.1]

### Changed

- **Instruction-surface punctuation.** Replaced em dashes in the plugin README
  with periods. YAML frontmatter and the `plugin.json` description are
  unchanged. No behavior change.

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command. The
  slash-command picker then echoed that back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed (breaking)

- **`ubiquitous-language` skill renamed to `curate-language`** (fleet conformance wave: naming
  grammar). Invocation changes from `/domain-driven-design:ubiquitous-language` to
  `/domain-driven-design:curate-language`; behavior is unchanged. The new name follows the
  verb-object skill-naming grammar. The domain term *ubiquitous language* the skill stewards keeps
  its name. Only the skill's invocation token changed. Consumers (including the `planning` plugin's
  cross-plugin invocation) must update to the new token.

## [0.1.0]

### Added

- **Initial release.** `/domain-driven-design:ubiquitous-language`, moved from the
  `planning` plugin, where it lived as `/planning:domain-modeling`. The skill maintains
  the consuming project's active ubiquitous-language glossary (canonical terms, rejected
  synonyms, what-it-IS definitions, routing among already-known bounded contexts) and
  explicitly refuses bounded-context discovery. The old name over-promised modeling. The
  concern is DDD language stewardship. `planning` now declares a dependency on this
  plugin, so its pipeline keeps invoking the skill cross-plugin.
