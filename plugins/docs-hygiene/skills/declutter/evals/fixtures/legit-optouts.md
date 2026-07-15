# Bar Convention

Defines the Bar convention for bar-related rule files.

## Convention body

The Bar convention requires every Bar-producing function to honor the BarContract interface.

<!-- markdown-discipline-ignore -->
Empirically observed 2026-04-22 on slice `bar-rollout`: skipping the BarContract step caused a regression in 3 downstream consumers. This narrative is legitimately inline because the incident drove the convention's existence and rewriting it as a footer would lose the prose-narrative shape that makes the rule's motivation legible. The opt-out marker above wraps this paragraph per the markdown-discipline.md opt-out convention.

The following paragraph carries no opt-out wrap and demonstrates a clean directive.

Bar values MUST be immutable post-construction. Mutability breaks downstream invariants.

<!-- markdown-discipline-ignore-line -->
Empirically observed 2026-05-01: this single citation line is opt-out-wrapped for teaching purposes.

## ADR amendment block

### 2026-04-30 amendment

Status amended from `proposed` to `accepted`. Bar contract finalized after stakeholder review.

### 2026-05-15 amendment

Status amended from `accepted` to `superseded by ADR-NNNN`. Bar replaced by Baz per ADR-NNNN.

## Recheck triggers

| Condition | Action |
|---|---|
| Bar consumer count exceeds 10 | Evaluate whether BarContract should be split |
| Downstream framework drops support for the BarContract pattern | Reconcile or migrate to successor pattern |

## Cross-references

- `baz-conventions.md` — Bar's successor convention per ADR-NNNN
- `review/architecture.md` "Dependency direction" — Bar inherits the layer rules

## Sources

- [Bar pattern in upstream framework](https://example.invalid/docs/bar) — original Bar shape this convention inherits
- `incident-2026-04-22.md` — incident driving the BarContract requirement (promoted from a retired slice per Promotion paths — `git log -- .work/bar-rollout/`)

## History

- 2026-04-30 — Bar contract finalized after stakeholder review
- 2026-05-15 — Bar superseded by Baz per ADR-NNNN
