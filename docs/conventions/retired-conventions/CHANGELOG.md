# Retired Conventions Convention — Changelog

Notable changes to the retired-conventions contract. Versioned by `contract_version` (SemVer),
governing the manifest schema, the helper CLI contract, the two fixed setup lines, the append-only
and demotion rules, the eval-per-record requirement, and the fleet sweep's finding contract. Which
surfaces retire is each plugin's own migration PR and is never versioned here. Adding a required
field, removing a field, changing a kind's detection semantics, an exit code's meaning, or the
severity map is a major bump; adding an optional field, a `status` value, or a new `kind` with its
own detection rule is a minor bump.

## 1.1 — 2026-09-02

Optional `heading` field on `kind: line`. When set, detection and `--clean` consider only matching
lines in the body of every markdown section whose ATX heading line equals the field (trailing
whitespace ignored). Unset `heading` keeps the 1.0 whole-file line rule. The field is frozen once
published, alongside `match` and `content_match`. Helper, validator, and owner-doc field table
updated together.

## 1.0 — 2026-09-01

Initial published contract, landing with the mechanism PR that ADR 0018 named (helper, validator,
sync registration, owner doc, audit-pass sweep lane, pointer-line resolver). No plugin ships a
manifest yet; the Implementers table is empty by design.

- Manifest: `plugins/<plugin>/retirements.yaml`, a flat YAML subset (`---`-separated records of
  flat `key: value` scalars). Fields `id`, `retired`, `plugin_version`, `kind`, `path`, `match`,
  `content_match`, `action`, `successor`, `note`, `status`. Unknown keys fail validation.
- Append-only with three enumerated legal edits: status flip, defect fix to `note`/`successor`,
  and demotion to `report-only` instead of pruning when a path is deliberately re-adopted (recorded
  in the plugin CHANGELOG). Deletion never.
- Helper: `lib/check-retirements.sh`, canonical in `claude-config`, synced byte-identical. TSV
  `id\tkind\tpath\taction\tstatus\tnote`; detection exit 0/1/2 (clean / active leftovers / error,
  with an invalid record failing the whole run); `--clean <id> [--i-migrated]` exit 0/1/2. Paths
  emitted repo-relative; consumer content only ever grep-matched.
- The two fixed setup lines (`check` and `apply`), conditional on the plugin shipping a manifest,
  with the severity map `migrate` FAIL / `delete`,`remove-line` WARN / `report-only` INFO, exit 2
  as a visible FAIL, and bash-unavailable as UNKNOWN. Wiring is CI-checked in both directions.
- One eval case per record id in the plugin's setup evals; validator failure when missing.
- Runtime fleet sweep as a `claude-config` audit-pass lane over installed plugins' manifests, using
  claude-config's own helper copy; read-only, no generator, no committed aggregate.
- Dual-read deprecation window bounds: a `migrate` record opens it; cleanup closes it per consumer;
  demotion to `report-only` closes it fleet-wide.
- Scope: repository-scope only; machine-scope surfaces excluded (ADR 0018).
- Deferred: the CI-aggregated fleet registry, revived only when orphan leftovers from an
  uninstalled plugin are observed in practice.
