# audit-pass — the run contract

The run contract is split per topic; this file routes to the part that owns each rule. The `§1`–`§7`
section numbering is unchanged and travels with the content, so every cross-reference inside the
contract — `§3`, `per 4.2`, `assertion 1.10a`, `§6's P2`, `§7's delimiters` — still resolves through
the map below.

| File | Sections | What it owns |
|---|---|---|
| [terms.md](terms.md) | preamble | The shared vocabulary: run, target, lane, scan set, live surface, live surface set. |
| [finding-identity.md](finding-identity.md) | §1 | The `(check, claim, sites)` tuple, `surface`, `anchor`, normalization, and the derived `finding_id`. |
| [report-location-and-schema.md](report-location-and-schema.md) | §2, §7 | Where the report is written, what `--report-to` may target, and the partial and assembled artifact schemas. |
| [run-state-and-resumability.md](run-state-and-resumability.md) | §3, §5 | The state key, the applying lock, the lease and its liveness test, and what `--resume` re-runs. |
| [suppression.md](suppression.md) | §4 | The central record, its cascade layers, and the four dispositions an entry resolves to. |
| [determinism-tiers.md](determinism-tiers.md) | §6 | The derived, judged, and delegated tiers, the comparability predicate, and P1–P6 with the determinism gate. |
