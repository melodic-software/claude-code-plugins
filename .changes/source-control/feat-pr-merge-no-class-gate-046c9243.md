---
bump: minor
---

### Changed

- The unattended merge gate no longer gates on work class. Eligibility reads no `work-class:` label except the trust hold: a pull request whose linked issue carries `work-class: untrusted-provenance`, or had it removed by a non-human, is still refused (`untrusted-provenance`, `untrusted-provenance-removed-by-non-human`), and unreadable issue labels refuse as `issue-labels-unreadable`. The `class-missing`, `class-unknown`, `class-provenance:*`, `class-label-removed-by-non-human` and `class-above-rung` refusals are gone.
- Eligibility now needs the linked issue vouched for by a human, refusing as `issue-not-vouched:<why>` otherwise. Either a write-access human wrote the issue, or one applied the tracker's admission label in person with no body edit after it. The admission label is the `autonomous-eligible` role in `.work-item-tracker.json` at the base branch, `agent-ready` by default. This takes the place of the class-label provenance check as the gate's human vouch.
- Promotion evidence no longer gates a merge, and the gate no longer reads it. Removed: both `promotion-unqualified:` refusals, the `unattended.promoted` field, and the promotion resolver call along with its demotion window restart (`--window-start`). After a demotion record closes, the rung returns without any promotion cell being re-ratified first. The rung, the rung cap and the demotion record still pace the gate.
- The risk score reads no work class: the `class-missing`, `class-above-rung`, `class-contradicted` and `blast-radius-missing` reasons are gone, and `RiskInput` drops `work_class`, `rung`, `blast_radius` and `c2_contradictions`. The gate no longer reads `merge.diff-check.c2-contradictions`. The key is deprecated with no effect, and the schema still accepts it.
