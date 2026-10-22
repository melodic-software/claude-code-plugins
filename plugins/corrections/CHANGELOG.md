# Changelog

All notable changes to the `corrections` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
