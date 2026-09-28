# provenance / attribution: repo-wide sweep parked; adopt-on-touch remains

## Decision

**Parked — no repo-wide sweep.** This repository does not run a fleet `sweep` of tracked
markdown for prose provenance
([#3465](https://github.com/melodic-software/claude-code-plugins/issues/3465)). Adopt-on-touch
stays in force: when a contributor edits a markdown file, they still apply
`/attribution:audit` (report) and, when a finding is fix-eligible, `/attribution:audit fix` on
that file. The `provenance` plugin is a rename shim; the live skill is `attribution`.

**Claim:** a disposition-applying corpus sweep stays blocked (golden set below
`min_n_per_class` 10, every class report-only), and an autonomous rerun of the report-only
fleet pass is unpaid epic work; per-file adopt-on-touch is the working rule. **Basis:** #3465
Brief (stage 2 gated on #3458 growth); `plugins/attribution/CHANGELOG.md` re-score (8 tp / 0 fp
/ 0 fn / 2 tn, n = 2, 5, 1, 2); triage 2026-09-06 (oversized; four open spec decisions). **As
of:** 2026-09-28. **Recheck:** golden-set classes reach `min_n_per_class` 10 at or above the
0.95 bar *and* a maintainer unparks #3465 with an explicit directory list.

## What stays

- **Adopt-on-touch.** Edit a file, run attribution on that file, apply only fix-eligible
  dispositions behind the semantic-diff guard. No per-instance suppression list.
- **Report-only `audit`.** Always allowed on a named target. It does not mutate.
- Stage-1 telemetry already recorded on the #3465 thread (2026-08-28 run; 2026-09-06
  re-measure). That record is not re-derived here.

## What does not run

- Repo-wide `sweep` (closure ledger, per-file close-the-file discipline across the corpus).
- Disposition-applying sweep (still arithmetically report-only at v1).
- Convention-engagement changelog plus cleaned-state CI gate (both fire at sweep completion).
- Building resume semantics, searched-surfaces mechanical floor, or golden-set growth as part
  of this settlement.

## Rationale

- Stage 1 already ran. Repeating it without answering the four open spec decisions (generated
  files, searched-surfaces floor, rubric v3 re-score scope, vendored-snapshot tier row) would
  re-litigate the same gaps.
- Stage 2 cannot apply dispositions until class size clears the gate. Forcing it would violate
  the plugin's own fix-eligibility arithmetic.
- Adopt-on-touch keeps the convention live without a priced fleet pass.

## Revisit when

- #3458 (or successor) carries `verbatim` and `near-verbatim` past n=10 at ≥ 0.95, and a
  maintainer unparks #3465, or
- A consuming team reports corpus-scale provenance drift that per-file adopt-on-touch cannot
  see.

## Prior requests

- #3465 (2026-09-28): provenance sweep sub-topic (repo-wide sweep, upstream-drift engagement,
  cleaned-state gate); drain shipper parks the fleet sweep and keeps adopt-on-touch (no sweep
  executed).
