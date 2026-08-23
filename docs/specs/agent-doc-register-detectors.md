# Agent-doc register detectors (D1–D3)

Close-out register for [#3118](https://github.com/melodic-software/claude-code-plugins/issues/3118).
The brief lived in that issue body; this file is the durable map of where each
cut class landed, so a later reader does not have to reconstruct the work-map
from closed children.

**No new skill.** Each class sits on the audit that already owned its
territory. Word count is a reported side effect, never an objective and never
a threshold.

## Register

| ID | Class | Home | What shipped | Issue |
|---|---|---|---|---|
| D1 | Content the model already knows — an instruction carrying no proper noun, path, threshold, version, or repo-specific fact | `claude-config:audit-instructions` → `/claude-config:unhobble` | **Routing finding, not a scanner.** The #3121 measurement (`d1-model-already-knows-measurement.md`) flagged 45.1% of instruction sentences at a 94.1% false-positive rate, with zero unambiguous true positives in the 185-row sample. The predicate is model-relative and cannot be read off the text. #3124 closed unbuilt. `audit-instructions` already states the boundary: it judges instruction *text* against doctrine; `unhobble` measures the *model*. D1 is a restatement of that Recommended-follow-through, never a `type: review-findings` row. | #3121, #3124, #3188 |
| D2 | Coercive emphasis — `CRITICAL:`, `You MUST`, all-caps imperatives, blanket "if in doubt, use X" | `claude-config:audit-instructions` | Scanner families `I28-a` / `I28-b`, body-scoped, wired to the findings relay as `rule-coercive-emphasis` and `rule-blanket-tool-default` (both IMPORTANT). | #3120 |
| D3 | Negation with no positive alternative in the same sentence | `docs-hygiene:audit-noise` | Shape `negation`, Tier 2, wired to the findings relay as `rule-negation-without-positive` (IMPORTANT). Hard-guardrail / paired-positive / worked-example carve-outs are evidence-gated. | #3123 |

## Hard constraint (all three)

No finding whose remediation edits a `description`, `when_to_use`, or quoted
`'trigger phrase'`. `plugins/skill-quality/scripts/check-skill.sh` check 3
hard-FAILs a dropped trigger phrase versus the base ref. Detectors are
body-scoped. A description-level concern is reported to the human, never
routed to the apply relay.

## Producer contract

D2 and D3 emit `type: review-findings` files that `review:fanout fix` locates
and applies behind the human gate, per
[`docs/conventions/detector-findings/README.md`](../conventions/detector-findings/README.md).
D1 never emits that file.

## Out of scope here

- Ceremonial-section removal by heading name — rejected in #3118; the
  restatement *shape* (body prose that restates the always-in-context
  `description`, or a sibling section) is D4, filed as #3186 and housed on
  `claude-config:audit-instructions` as a D1 sibling.
- Length or token-count targets of any kind.
- Human-facing prose (`docs-hygiene:write-for-humans`).
- A new apply-side skill. The apply relay exists.

## Specs this register points at

- [`d1-model-already-knows-measurement.md`](d1-model-already-knows-measurement.md) — D1 verdict, method, and the 94.1% bar.
- [`agent-doc-surfaces.md`](agent-doc-surfaces.md) — the surface enumeration the D1 corpus was drawn from.
