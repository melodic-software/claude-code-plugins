# native-design-surfaces

## Brief

Signed off by the user 2026-09-01 ("accept all" on the V2 round; full question history in
`.work/native-design-surfaces/interview-checklist.md`, Q1-Q12 all answered). This vertical came
out deliberately small: its decisions ride along inside the playground-integration single
delivery PR (user directive 2026-09-01: one session, one feature branch, one PR).

### TLDR

- Record the already-live design-canvas overlap: two human-gated `complementary` verdict rows
  (bundled `design` skill vs `visualization:visualize`, vs `prototype:explore-directions`) via the
  audit-native-overlap pipeline, using the existing `bundled-skill` native class and `extraction`
  observation class (no engine change needed for these).
- Record the design-sync family (design-sync, design-consent, design-revoke, design-login,
  DesignSync tool) as an observed `defer` row: real enough to record, no use case to rule on.
- Refresh the visualize catalog spoke's design-canvas facts from v2.1.234 to v2.1.251 (subcommand
  dispatch incl. consent/revoke, the full family) and update its verified-on line.
- No design-sync integration, wrapper, or routing work.

### Goal

The registry that owns native-overlap knowledge records this repo's deepest live native
integration (the design-canvas presence gates in two skills) and the newly observed design-sync
family, and the catalog facts those skills rest on are current, so future audits and rechecks
fire from recorded triggers instead of tribal memory.

### Constraints

- Verdicts through the audit-native-overlap pipeline, human-gated, evidence citing this
  session's v2.1.251 binary extraction (dated 2026-08-31/2026-09-01) and the corpus digests.
- The design-sync family row is observation-only (the `morning` precedent): never baked into any
  skill text, no suggestion lines, until a real use case reopens it.
- Visualize's semantic boundary is unchanged: it keeps only the canvas row; design-system sync is
  publishing, not visualization, and its skill is model-invocation-disabled upstream.
- Changes ship inside the playground-integration PR sequence (after its leading engine PR), not
  as a separate effort.

### Acceptance criteria

- `docs/native-surfaces/records.json` carries the two design-canvas rows (expected verdict
  `complementary`; final wording human-gated at recording time) and one design-family `defer`
  row, all passing `overlap.py generate --check` and `self-check`; `docs/NATIVE-SURFACES.md`
  regenerated in the same PR.
- `plugins/visualization/skills/visualize/context/decision-matrix.md`'s design-canvas section
  reflects v2.1.251 (subcommand dispatch; consent/revoke handled as user-run commands; family
  members named) with an updated verified-on/recheck line.
- No file gains design-sync routing, suggestion, or install text.

### Captured assumptions

- The design family remains rollout-flag-gated and research-preview; recheck triggers on the
  next Claude Code release that names any of design/design-sync/design-consent/design-revoke in
  its changelog or commands reference (through v2.1.251 none are documented).
- No claude.ai/design usage exists among this repo's operators today — revisit the defer row if
  that changes.

### Out-of-scope

- Any design-sync/consent/revoke integration or wrapper.
- /design routing beyond the presence gates visualize and explore-directions already carry.
- Artifact-capability work (paste-back bridges, connector dashboards) — future verticals.

### Deferred questions

None. (Q1-Q12 in the ledger are all answered; nothing deferred from this vertical.)

## Plan

Executed as Phases 5-6 of `docs/topics/playground-integration/PLAN.md`'s Plan (single delivery
PR); no separate plan of its own.
