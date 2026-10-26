# Changelog

All notable changes to the `corrections` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
