# pr-merge promotion binding

`.github/workflows/pr-merge.yml` reads two things from this folder on `main`:

- `binding.json`: the security binding whose `promotion_state` says which cells the owner has
  promoted (`C2-auto-merge`, `C3-auto-merge`). Its format is the autonomy plugin's
  `guardrails-security-binding.schema.json`. While the file is absent, every cell reads
  unpromoted and the lane merges nothing.
- This folder itself, as the probe-evidence root: the binding's `probe_evidence` references are
  paths relative to it.

The folder sits under `docs/conventions/**`, a denied path, so the lane never merges a change here.

## Re-ratify cadence

A promoted cell expires 85 days after its `ratified_at`: past that, the check fails closed for the
whole binding (`epoch-start-expired`), because GitHub may have deleted older contrary evidence.
Re-ratify each promoted cell, with a new `ratified_at` and `ratified_by_change`, before 85 days
pass; about every 80 days leaves time for review. The rule and its source are in the
source-control plugin's `promotion-evidence-resolution.md`, "Inline mode".
