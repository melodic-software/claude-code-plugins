---
bump: minor
---

### Changed

- The unattended merge gate no longer gates on work class. Eligibility reads no `work-class:` label except the trust hold: a pull request whose linked issue carries `work-class: untrusted-provenance`, or had it removed by a non-human, is still refused (`untrusted-provenance`, `untrusted-provenance-removed-by-non-human`), and unreadable issue labels refuse as `issue-labels-unreadable`. The `class-missing`, `class-unknown`, `class-provenance:*`, `class-label-removed-by-non-human` and `class-above-rung` refusals are gone.
- Promotion evidence no longer gates a merge: both `promotion-unqualified:` refusals and the `unattended.promoted` field are gone. The evidence is still read and reported under `unattended.promotion`. The rung and the rung cap still pace the gate.
- The risk score reads no work class: the `class-missing`, `class-above-rung`, `class-contradicted` and `blast-radius-missing` reasons are gone, and `RiskInput` drops `work_class`, `rung`, `blast_radius` and `c2_contradictions`. `merge.diff-check.c2-contradictions` is still read but scores nothing.
