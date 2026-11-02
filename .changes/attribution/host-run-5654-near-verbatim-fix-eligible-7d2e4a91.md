---
bump: minor
---

### Changed

- **`/attribution:audit fix` and `sweep` now reach `near-verbatim` copies.** The owner declared the
  class fix-eligible on 2026-11-02
  ([#5654](https://github.com/melodic-software/claude-code-plugins/issues/5654#issuecomment-6578852154)),
  on the 0.14.12 re-score: n 15, precision 1.00, recall 0.93, binding gate, six distinct origin
  pages. A finding is fix-eligible only when its class is `near-verbatim` and its tier is
  `fingerprint-confirmed`; every per-finding guard is unchanged (identity-checked live source,
  unanimous panel, review veto, matched-span fence, pointer liveness, semantic-diff revert).
  `verbatim`, `paraphrase`, `summary` and `restated-fact` stay report-only. The rule is stated
  once, in `reference/dispositions.md` "Fix eligibility"; `SKILL.md`, the rubric's tier table and
  the README point at it. Golden-set evals 9 and 14 now expect the near-verbatim findings to be
  reported as fix-eligible.
