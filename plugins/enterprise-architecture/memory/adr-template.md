# ADR Template

Standard template for Architecture Decision Records (ADRs).

## File Naming Convention

```text
/architecture/adr/
  0001-initial-architecture.md
  0002-database-selection.md
  0003-api-design-approach.md
```

## Template

```markdown
# ADR-[NUMBER]: [TITLE]

## Status

| Status | Description |
| ------ | ----------- |
| Proposed | Decision is under review |
| Accepted | Decision has been approved and implemented |
| Deprecated | Decision is no longer recommended but may still exist in code |
| Superseded | Decision has been replaced by another ADR |

If superseded, link: Superseded by [ADR-XXXX](./XXXX-title.md)

## Date

YYYY-MM-DD

## Deciders

- [Name/Role]
- [Name/Role]

## Context

[Describe the context and problem. What forces are at play? What constraints exist?]

## Decision

[State the decision clearly. Use active voice: "We will..."]

## Consequences

### Positive

- [Benefit 1]
- [Benefit 2]

### Negative

- [Drawback 1]
- [Drawback 2]

### Neutral

- [Side effect 1]

## Alternatives Considered

### Alternative 1: [Name]

[Description]

**Pros:** [List]
**Cons:** [List]
**Why not chosen:** [Reason]

### Alternative 2: [Name]

[Similar structure]

## Related Decisions

- [ADR-XXXX](./XXXX-title.md) - [Relationship]
- [ADR-YYYY](./YYYY-title.md) - [Relationship]

## References

- [Link to relevant documentation]
- [Link to related resources]
```

## Status Transitions

```text
Proposed → Accepted → [Deprecated | Superseded]
                    ↘ Still valid (no change)
```

**Proposed:** Decision is under review
**Accepted:** Decision is approved and in effect
**Deprecated:** Decision is no longer recommended but may still exist in code
**Superseded:** Decision has been replaced by another ADR

## Best Practices

1. **One decision per ADR** - Keep focused
2. **Immutable once accepted** - Create new ADR to change
3. **Include context** - Future readers need to understand why
4. **Document alternatives** - Show due diligence
5. **Link related ADRs** - Build decision network
6. **Keep current** - Update status when decisions change

## When to Create an ADR

- Technology selection (database, framework, language)
- Architecture patterns (microservices, event-driven, etc.)
- Design approaches (API style, authentication method)
- Build/deployment decisions (CI/CD, containerization)
- Significant trade-offs (performance vs maintainability)

## When NOT to Create an ADR

- Trivial decisions with obvious answers
- Temporary workarounds
- Implementation details that can easily change

---

**Last Updated:** 2025-12-05
