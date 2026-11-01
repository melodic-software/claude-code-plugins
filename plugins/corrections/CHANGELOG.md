# Changelog

All notable changes to the `corrections` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.9.1] - 2026-11-01

### Changed

- `codify`'s enforcement-ladder copy, now 2.1.0, names `/corrections:codify` as the reader that picks a rung for a recurring mistake, a findings file or review comments, and its Boundary no longer names the older review and retro surfaces.

## [0.9.0] - 2026-11-01

### Added

- `/corrections:codify findings <findings-file>` takes each row of one review findings file through the count, rung and proof steps, strongest rung first, and writes one proposal per row. `reference/finding-classes.md` holds the class lookup and each rung's next step.
- `/corrections:codify reviews` mines recent merged pull requests' review comments through `/source-control:pull-request review-comments`; the PR author's own comments made after the merge count.
- `ratchet_offer` and `review_mining_prs` settings and plugin options, resolved by `codify-settings.mjs`; `corrections.yaml` wins over the option, and an invalid repository value falls to the default.
- The codify report names the chosen rung by its ladder id and reports a recurring checkable mistake with no check as a "no guardrail" finding naming the ladder's "Guardrail criterion" section; a rule that was never loaded is fixed where it lives as well as taking its checking rung.
- An eval suite under `evals/` with deterministic graders for both inputs and the behavior ported from `/review:audit-enforceability` and `/session-flow:retro codify`.

### Changed

- The config cascade skips the setup writer's top-level `written_against` and `provenance` keys, so
  neither reaches `values`, a layer's errors or a userConfig name.

## [0.8.12] - 2026-10-31

### Fixed

- The convention-home resolver refuses a pointer that names `.git` or a path inside it, and a
  working-tree home reached through a symlink: both exit 3.

## [0.8.11] - 2026-10-30

### Changed

- The generated plugin-options block in this plugin's docs now links `docs/contracts/<name>/` instead of the old `docs/conventions/<name>/` stub.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.8.10] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.8.9] - 2026-10-30

### Changed

- `yaml-subset.mjs` gains a `source` option that keeps each scalar as its source text. Default parsing is unchanged (#10131).

## [0.8.8] - 2026-10-29

### Changed

- Synced contract copies name their canonical source at `docs/contracts/<name>/`, where the plugin contracts moved from `docs/conventions/<name>/`.

## [0.8.7] - 2026-10-29

### Changed

- The generated README "How to set these" block names `claude plugin configure <plugin>@<marketplace> --values-stdin` as the preferred headless route, per the plugin-reconfiguration convention, and keeps the `claude plugin install --config` rerun only as its fallback.

## [0.8.6] - 2026-10-29

### Changed

- The config reader now refuses a plain YAML value holding a colon and a space (such as `label: needs: triage`) and a plain key holding whitespace, `$` or `.` (such as `$schema: x` or `a.b: c`), naming the line. One such line now makes the whole file invalid, where the value used to be read as text or the key reported on its own. Quote the value or key to keep it.

## [0.8.5] - 2026-10-28

### Fixed

- The shared config resolver now tags each layer error with the key it names (`error_keys`, null for a
  file-level error), so a reader can tell a key-level error from a whole-file one.

## [0.8.4] - 2026-10-27

### Changed

- The README's generated "How to set these" block no longer restates Claude Code CLI and settings behavior as fact. Each upstream specific is now a link to the docs section that owns it (`/plugin` in a session, what an uninstall deletes and keeps, `pluginConfigs`), and what this repository measured stays in the plugin-reconfiguration convention.

## [0.8.3] - 2026-10-27

### Fixed

- **The findings buffer redacts bare `sk-ant-oat01-` tokens and dotted `ghs_` tokens whole ([#9026](https://github.com/melodic-software/claude-code-plugins/issues/9026)).** Its copy of `redact.py` now runs two of its own rules before the vendored gitleaks rules. Before this, a bare `sk-ant-oat01-` value reached the adapter unredacted, and the vendored `github-app-token` rule replaced only the first 36 characters of a stateless `ghs_` token containing a dot, so the rest of the token stayed in the row.

## [0.8.2] - 2026-10-27

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.

## [0.8.1] - 2026-10-27

### Fixed

- The `local-file` findings buffer's `append.sh` takes perl's `flock` on `.work/buffer/.lock` where `flock` is absent and perl calls flock(2) itself, so an appender killed with SIGKILL no longer leaves a lock that fails every later append until an operator removes it. Where neither is available, the `.lockdir` lock stays as before.

## [0.8.0] - 2026-10-26

### Added

- `scripts/group-findings.mjs [--by <field>[,<field>...]] [--since <UTC ISO-8601>] [--rows]` runs `buffer.sh read` and prints the findings buffer grouped by the named top-level fields (default `producer`): a first line naming the keys, then each group with its row count, its occurrence count (distinct `source_id`) and its members, most occurrences first. `--since` cuts exactly, fraction included, and row values print with control, format (bidirectional and zero-width included) and separator characters escaped.

### Changed

- `/corrections:codify group` takes `--by`, runs `group-findings.mjs`, shows the field groups, then groups by mistake, and names the keys of both groupings.

## [0.7.2] - 2026-10-26

### Fixed

- `scripts/lib/yaml-subset.mjs` reads an empty sequence item (`-` alone) as `null` when the next line is another item at the same indent, instead of nesting the following items under it.
- A quoted key may hold a doubled `''` in single quotes or a `\"` escape in double quotes; such a key no longer fails with `expected a mapping entry`.

## [0.7.1] - 2026-10-26

### Fixed

- `scripts/codify-settings.mjs` and `scripts/findings-buffer.mjs` print at most the first five errors per settings layer, then `and N more`, so a committed `corrections.yaml` or `findings-buffer.yaml` full of unknown keys no longer floods stderr.
- `recurrence.min_occurrences` now has a maximum of 1000; a larger value is dropped with a note on stderr and the threshold falls back as for any invalid value.

## [0.7.0] - 2026-10-25

### Added

- A repository's own findings-buffer adapter can be bound in user scope, through two new `userConfig` options: `findings_buffer_adapter_repository`, the git common directory of the one repository it applies to, and `findings_buffer_adapter_path`, the adapter directory relative to the checkout root. `buffer.sh` reads them from user and managed settings only, never from the environment, a project settings file or the repository's binding files, which still name only adapters the plugin ships. The binding applies in that repository's main checkout and its worktrees and in no other repository, and the adapter must resolve inside the current checkout, outside any nested repository, and pass the existing verb and `capabilities.json` checks.
- A generated copy of the shared `lib/plugin-options.mjs` settings reader, under `scripts/lib/`.

## [0.6.2] - 2026-10-25

### Changed

- The findings buffer's `lib/redact.py` is now generated from the repository's shared `lib/redact.py` rather than from a file inside the session-flow plugin's skill folder; only its generated-file header changed.

## [0.6.1] - 2026-10-25

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#9684): `detect.version` accepts an exclusive `below` bound; no other change to this plugin.

## [0.6.0] - 2026-10-22

### Added

- `/corrections:codify note` appends one observation to the findings buffer, and `/corrections:codify group` reads the buffer and groups its rows by mistake, showing each group's count next to the recurrence threshold. `group` writes nothing.

## [0.5.0] - 2026-10-22

### Changed

- `/corrections:codify` reads its recurrence threshold from the `recurrence.min_occurrences` setting
  (default 2) instead of a fixed 2, and reports the layer that set it. The team file is
  `<home>/corrections.yaml`, the personal overlay `<home>/corrections.local.yaml`, `<home>` the
  convention home (default `docs/conventions`). A person's direct "codify this" still acts at once,
  whatever the count.

### Added

- `scripts/codify-settings.mjs` and `schemas/corrections.schema.json`, which resolve the setting
  through the config cascade and print the value and its layer; an invalid value is named on stderr
  and falls back.

## [0.4.0] - 2026-10-21

### Added

- `tools/findings-buffer/buffer.sh append|read [--since <UTC ISO-8601>]`: the findings-buffer core.
  It picks the adapter from `<home>/findings-buffer.yaml` (overlay `findings-buffer.local.yaml`,
  default `local-file`) through the config cascade. Only adapters the plugin ships under
  `tools/findings-buffer/adapters/` are run; a binding naming a repository path is refused, so a
  cloned repository cannot make the buffer run its own code. `append` redacts string values with the vendored gitleaks rules, caps each row at 2048
  bytes, sets `obs_id` and `ts`, and falls back to `local-file` when the bound adapter's append
  fails. `read` merges the bound adapter's rows with the `local-file` rows and drops repeat
  `obs_id`s.
- `scripts/findings-buffer.mjs` and `schemas/findings-buffer.schema.json`, which resolve the binding,
  cap rows, assign `obs_id` and dedupe.
- Generated copies of `lib/config-cascade.mjs`, `lib/yaml-subset.mjs`,
  `lib/resolve-convention-home.sh` and session-flow's `redact.py`, and the vendored gitleaks rules
  under `tools/findings-buffer/vendor/gitleaks/`.
- `prerequisites.json` declares `node` and `python3`, which `buffer.sh` runs.

## [0.3.0] - 2026-10-21

### Added

- `tools/findings-buffer/CONTRACT.md`: the findings-buffer seam. An append-only pool with two verbs
  (`append.sh < rows.jsonl`, `read.sh [--since <UTC ISO-8601>]`), a `capabilities.json` handshake
  (`schema_version` `1.0`), exit codes `0`, `2`, `3`, and the rule that transcript-derived rows never
  leave the machine.
- `tools/findings-buffer/adapters/local-file/`: the `local-file` adapter, storing rows in
  `.work/buffer/findings.jsonl` under the repository root with locked appends.
- `tools/findings-buffer/conformance.sh <adapter-dir>` and `conformance.test.sh`: the conformance
  check every adapter must pass, including 8 concurrent appends.
- `prerequisites.json`: declares `jq` (optional for the plugin; only the findings-buffer tool needs
  it), which the `local-file` adapter uses to validate and filter rows and `conformance.sh` uses to
  parse `capabilities.json`.

## [0.2.0] - 2026-10-21

### Added

- `/corrections:codify "<description>" [#PR]`: counts earlier occurrences of a described mistake in
  recent commits and the session (threshold 2; a person's direct "codify this" acts at once), picks
  the strongest enforcement-ladder rung that can decide it, places the lesson by scope, and proposes a
  check proven with `scripts/prove-check.sh`. An unproven check is reported and never proposed for
  install. A person's invocation writes the proposal, a model invocation only proposes, and a blocking
  check is asked about before every install. An escaped defect's proposal also names what the model
  did not have in front of it.
- The enforcement ladder 2.0.0 as a registered shared copy under `skills/codify/reference/`.
- Five eval cases for the skill.

## [0.1.0] - 2026-10-21

### Added

- `scripts/prove-check.sh --check '<command>' --old <ref> [--new <ref>]`: runs a proposed check in
  temporary worktrees at two refs and exits 0 only when it fails at the old ref and passes at the new
  one (default `HEAD`); exit 1 when the proof fails, 2 on a usage error. Both worktrees are removed on
  every exit path.
- `scripts/prove-check.test.sh`: five cases against a fixture repository with a planted violation.
