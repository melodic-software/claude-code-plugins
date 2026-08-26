# L1-derivability — `A-doc-quality`

78 files. `ai-slop`, `docs-hygiene`, `markdown-format`, `typos-format`.

| Verdict | Count |
|---|---:|
| `keep-owns-facts` | 52 |
| `out-of-scope: functional artifact` | 26 |

No deletions, no pointer conversions, no cache verdicts.

Roll-up for the 52 `keep-owns-facts`: skill bodies, `reference/` and `context/` sub-docs,
CHANGELOGs and plugin READMEs. The `ai-slop` rule catalog and rewrite guide are distilled from an
external, revision-pinned source (Wikipedia's "Signs of AI writing") with an overlap map against
Cursor's `unslop` skill recording what the port took, deduplicated, and rejected. That
took/deduplicated/rejected record is the Factor 4 "decisions" class and cannot be re-derived from
either source. The `docs-hygiene` rubrics are this sweep's own governing doctrine.

Twenty-six files are functional artifacts and take no verdict: the `**/evals/fixtures/**` trees for
`ai-slop`, `docs-hygiene/audit-noise`, `docs-hygiene/audit-progressive-disclosure`,
`docs-hygiene/audit-derivability`, `docs-hygiene/compress`, and `docs-hygiene/write-for-agents`.
These are eval inputs whose whole purpose is to carry the defect a detector must find; grading them
as documents would misread deliberate defects as findings. Note in particular
`plugins/docs-hygiene/skills/audit-progressive-disclosure/evals/fixtures/broken-skill/**`, which is
a deliberately broken skill.

## A note for the orchestrator

This group contains the rubric this lane runs on
(`plugins/docs-hygiene/skills/audit-derivability/SKILL.md` and
`context/rubric.md`) and the in-tree follow-up ledger from the previous repo-wide pass
(`plugins/docs-hygiene/context/derivability-route-followups.md`). The ledger is `keep-owns-facts`
and load-bearing for this sweep: it records the 2026-08-15 dispositions that calibrate how much
derivability debt this corpus had left, and the false-keep sampling backlog it defers.
