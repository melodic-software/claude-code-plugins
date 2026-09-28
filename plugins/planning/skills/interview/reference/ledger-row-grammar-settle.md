# Interview ledger row grammar — settle (#4611)

Full redesign is deferred. This record parks the issue until a human approves Option A.

## Decision record

- **Claim:** The per-shape escaped forms added in PR #4547 still lose structure on four
  round-trip paths (unconfirmed commitments, open seeded rows with later confirmations, superseded
  rows reconfirmed by accept, defer on superseded rows). Fixing each shape again is Option B;
  replacing the escapes with one ordered field grammar is Option A.
- **Basis:** Issue [#4611](https://github.com/melodic-software/claude-code-plugins/issues/4611);
  reproduction at `3dce37a59` (export → import → inspect `questions.json`).
- **As of:** 2026-09-28.

## Options

| Option | Scope | When to choose |
| --- | --- | --- |
| **A — Unified row grammar** | One escaped resolution per row with named fields (`hold`, `proposal`, `was`, `answer`, `note`, `aside`, `commitments` with per-item confirmed marks); import refuses unknown fields; property test over all status/hold/decision combinations | Preferred when a human approves the structural migration in #4611 |
| **B — Per-shape patches** | Add another escape variant per failing row shape | Rejected for autonomous work: repeats the loss class PR #4547 already hit |

## Park

No exporter or importer change ships until Option A is approved. Track implementation under #4611
with a user-approved PLAN covering Brief/report rendering, backward-compatible readers for legacy
rows, and the property test the issue specifies.
