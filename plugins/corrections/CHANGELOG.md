# Changelog

All notable changes to the `corrections` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
