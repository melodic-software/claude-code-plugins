---
name: gap-analysis
description: Compare current state to target state architecture. Scoped to technical options - requires business context for complete analysis.
allowed-tools: Read, Glob, Grep, Skill
---

# Gap Analysis

## When to Use This Skill

Use this skill when you need to:

- Document current (as-is) architecture
- Define target (to-be) architecture
- Identify gaps between current and target states
- Explore technical migration options

**Keywords:** gap analysis, current state, target state, as-is, to-be, roadmap, migration, baseline, transition

## Scope Warning

> **IMPORTANT:** This analysis covers **technical migration options** based on code structure.
>
> Complete migration planning requires business context including:
>
> - Budgets and timelines (external to code)
> - Organizational structure (external to code)
> - Technical debt priorities (partially in code)
> - Resource availability (external to code)
>
> Use this as **input to broader planning discussions**, not as a complete migration strategy.

## Gap Analysis Workflow

### 1. Document Current State (As-Is)

What can be extracted from code (Zachman rows 4-6):

| Aspect | Source | Analysis |
| --- | --- | --- |
| Technology stack | package.json, pom.xml, etc. | Frameworks, libraries, versions |
| Architecture patterns | Code structure | Monolith, microservices, layers |
| Data storage | Config files | Databases, caches, queues |
| Integration points | API definitions | REST, GraphQL, messaging |
| Infrastructure | IaC files | Cloud resources, networking |

What requires human input (Zachman rows 1-3):

| Aspect | Source Needed |
| --- | --- |
| Business capabilities | Business documentation |
| Process flows | Stakeholder interviews |
| Strategic alignment | Strategy documents |

### 2. Define Target State (To-Be)

Target state should include:

- **Vision statement**: What does success look like?
- **Technology targets**: Specific technologies, versions
- **Architecture targets**: Patterns, structures
- **Quality attributes**: Performance, scalability, security targets
- **Constraints**: Budget, timeline, compliance requirements

### 3. Identify Gaps

For each architecture dimension:

| Dimension | Current | Target | Gap |
| --- | --- | --- | --- |
| Compute | VM-based | Containerized | Container adoption |
| Data | Monolithic DB | Service-per-DB | Database decomposition |
| Integration | Point-to-point | Event-driven | Event mesh implementation |
| ... | ... | ... | ... |

### 4. Categorize Gaps

Classify each gap by:

**Type:**

- Technical debt
- Missing capability
- Scalability limitation
- Security vulnerability
- Compliance gap

**Complexity:**

- Low: Configuration change
- Medium: Code modification
- High: Architectural change
- Very High: Platform migration

**Risk:**

- Low: Isolated change
- Medium: Cross-component impact
- High: System-wide impact

### 5. Explore Options

For each gap, document:

```markdown
## Gap: [Gap Name]

### Current State
[Description of current situation]

### Target State
[Description of desired situation]

### Technical Options

#### Option A: [Name]
- **Approach**: [Description]
- **Pros**: [List]
- **Cons**: [List]
- **Technical complexity**: [Low/Medium/High]
- **Dependencies**: [List]

#### Option B: [Name]
- **Approach**: [Description]
- **Pros**: [List]
- **Cons**: [List]
- **Technical complexity**: [Low/Medium/High]
- **Dependencies**: [List]

### Recommendation
[Technical recommendation with rationale]

### Business Context Required
[What business input is needed to finalize decision]
```

## Gap Analysis Output Structure

```markdown
# Gap Analysis: [System Name]

**Date**: YYYY-MM-DD
**Scope**: [What's included/excluded]

## Scope Limitations

This analysis covers technical migration options based on code structure analysis.
Complete migration planning requires additional business context:
- Budget constraints and approval processes
- Team capacity and skill availability
- Business timeline requirements
- Risk tolerance and compliance needs

These options should inform broader planning discussions, not replace them.

## Current State Summary
[Overview of as-is architecture]

## Target State Summary
[Overview of to-be architecture]

## Gap Inventory

| ID | Gap | Type | Complexity | Priority |
|----|-----|------|------------|----------|
| G1 | ... | ... | ... | TBD |
| G2 | ... | ... | ... | TBD |

## Detailed Gap Analysis

### G1: [Gap Name]
[Detailed analysis per template above]

## Technical Dependencies
[Dependency graph showing which gaps must be addressed first]

## Recommended Sequencing
[Technical sequencing based on dependencies]

## Business Decisions Required
[List of decisions that require business input]
```

## Integration with Other Skills

- **architecture-documentation**: Generate current state documentation
- **zachman-analysis**: Ensure gaps cover all relevant perspectives
- **togaf-guidance**: Align with TOGAF Phase E (Opportunities & Solutions)
- **adr-management**: Create ADRs for gap resolution decisions

## Repository Location

Gap analysis documents should be stored at:

```text
/architecture/
  gap-analysis.md
  /transitions/
    transition-1.md
    transition-2.md
```

## Version History

- **v1.0.0** (2025-12-05): Initial release
  - Current/target state analysis workflow
  - Gap categorization (type, complexity, risk)
  - Technical options exploration
  - Explicit scope limitations (requires business context)

---

## Last Updated

**Date:** 2025-12-05
**Model:** claude-opus-4-5-20251101
