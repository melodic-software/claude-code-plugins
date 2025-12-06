# Architecture Principles Template

Architecture principles guide decision-making and provide rationale for choices.

## Principle Structure

Each principle should include:

```markdown
## [Principle ID]: [Principle Name]

**Category:** [Business | Data | Application | Technology]

**Statement:** [Clear, actionable statement of the principle]

**Rationale:** [Why this principle matters]

**Implications:**
- [What this means in practice]
- [Constraints it creates]
- [Behaviors it encourages]
```

## Example Principles

### Business Principles

```markdown
## B1: Business Continuity

**Category:** Business

**Statement:** Operations must continue despite component failures.

**Rationale:** Revenue loss and customer trust damage from outages exceed the cost of redundancy.

**Implications:**
- Design for failure - assume components will fail
- Implement redundancy at critical points
- Regular disaster recovery testing required
- Document recovery procedures
```

### Data Principles

```markdown
## D1: Data is a Shared Asset

**Category:** Data

**Statement:** Data belongs to the organization, not individual applications.

**Rationale:** Data silos prevent insights and create inconsistencies.

**Implications:**
- Establish data ownership and stewardship
- Create canonical data models
- Implement data governance
- Enable controlled data sharing
```

```markdown
## D2: Data Quality at Source

**Category:** Data

**Statement:** Data quality must be ensured at the point of creation.

**Rationale:** Fixing data quality issues downstream is exponentially more expensive.

**Implications:**
- Validate data at input
- Define data quality rules
- Monitor data quality metrics
- Reject invalid data early
```

### Application Principles

```markdown
## A1: Loose Coupling

**Category:** Application

**Statement:** Systems should minimize dependencies on other systems' implementations.

**Rationale:** Tight coupling creates fragility and inhibits independent evolution.

**Implications:**
- Use well-defined interfaces
- Prefer asynchronous communication
- Version APIs explicitly
- Design for independent deployment
```

```markdown
## A2: Prefer Standard Solutions

**Category:** Application

**Statement:** Use standard, proven solutions over custom development when possible.

**Rationale:** Custom solutions incur ongoing maintenance costs and risk.

**Implications:**
- Evaluate buy/adopt vs build
- Document reasons for custom development
- Use popular, well-supported frameworks
- Avoid vendor lock-in where practical
```

### Technology Principles

```markdown
## T1: Technology Standards

**Category:** Technology

**Statement:** Use approved technologies from the technology portfolio.

**Rationale:** Standardization reduces complexity, training costs, and support burden.

**Implications:**
- Maintain approved technology list
- Require ADR for non-standard choices
- Plan migration paths for legacy tech
- Regular technology portfolio review
```

```markdown
## T2: Cloud-First

**Category:** Technology

**Statement:** Prefer cloud services over on-premises infrastructure.

**Rationale:** Cloud provides elasticity, reduced capital expenditure, and operational efficiency.

**Implications:**
- Design for cloud-native patterns
- Consider managed services first
- Plan for multi-region deployment
- Address cloud security requirements
```

## Creating Your Principles File

1. Create `/architecture/principles.md` in your repository
2. Start with 5-10 high-impact principles
3. Ensure principles don't conflict
4. Get stakeholder buy-in
5. Review and evolve periodically

## Principle Validation

The `principles-validator` agent checks code against principles:

```markdown
## Using Principles for Validation

1. Each principle should have testable implications
2. Implications should map to code patterns
3. Violations should have clear remediation

### Example Mapping

- **Principle:** A1 (Loose Coupling)
- **Implication:** "Use well-defined interfaces"
- **Code Pattern:** Check for interface usage, dependency injection
- **Violation:** Direct instantiation in business logic
- **Remediation:** Introduce interface and DI
```

## Anti-Patterns

**Too many principles:**

- Start small (5-10)
- Add as needed
- Remove when obsolete

**Conflicting principles:**

- Review for conflicts
- Add precedence when needed
- Document trade-offs

**Unactionable principles:**

- Must have clear implications
- Should be testable
- Avoid platitudes

**Ignored principles:**

- Review and remove if not followed
- Investigate why not followed
- Evolve or enforce

---

**Last Updated:** 2025-12-05
