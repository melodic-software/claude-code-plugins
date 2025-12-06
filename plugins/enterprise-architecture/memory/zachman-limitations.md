# Zachman Framework: Code Extraction Limitations

This document outlines what can and cannot be extracted from code analysis when applying the Zachman Framework.

## Capability Matrix

| Row | Perspective | Code Extraction | Confidence | Notes |
| --- | ----------- | --------------- | ---------- | ----- |
| 1 | Planner/Executive | **Cannot extract** | N/A | Requires strategic context |
| 2 | Owner/Business | **Cannot extract** | N/A | Requires business documentation |
| 3 | Designer/Architect | **Partial** | Low-Medium | Structure visible; rationale missing |
| 4 | Builder/Engineer | **Strong** | High | Technologies, specs in code |
| 5 | Subcontractor/Technician | **Strong** | High | Configs, implementations |
| 6 | User/Operations | **Limited** | Medium | Requires runtime/deployment data |

## What This Means

### Rows 4-5: Strong Extraction (Can Do)

The plugin can reliably extract and analyze:

**Row 4 (Builder):**

- Data models, schemas, types
- Technology stack and versions
- Architecture patterns
- API definitions
- Build configurations

**Row 5 (Subcontractor):**

- Configuration files
- Environment settings
- Deployment manifests
- Infrastructure as code
- Detailed implementations

### Row 6: Limited Extraction (Partial)

Can extract with caveats:

**What we can find:**

- Deployment configurations
- Monitoring setup
- Logging patterns
- Runbook references

**What we cannot find:**

- Actual runtime behavior
- Production metrics
- User interaction patterns
- Operational issues

**Requires:** Access to running systems, monitoring data

### Row 3: Partial Extraction (Guidance Only)

Can infer structure but not intent:

```text
**What we can find:**

- Architecture structure
- Component relationships
- Interface definitions
- Layering patterns

**What we cannot find:**

- Design rationale (why this pattern?)
- Trade-off decisions
- Rejected alternatives
- Quality attribute priorities

**Requires:** ADRs, design documents, architect input
```

### Rows 1-2: Cannot Extract (Human Input Required)

These perspectives require business context that doesn't exist in code:

**Row 1 (Planner/Executive):**

- Business strategy
- Market positioning
- Organizational goals
- Investment priorities

**Row 2 (Owner/Business):**

- Business processes
- Capability definitions
- Value streams
- Business rules

**Requires:** Strategy documents, stakeholder interviews, business documentation

## Guidance for Non-Extractable Rows

When asked to analyze rows 1-3, the plugin should:

1. **Acknowledge the limitation** - Be clear that code analysis alone cannot provide this perspective
2. **Provide structured interview questions** - Help gather necessary input
3. **Suggest documents to review** - Point to where this information typically lives
4. **Offer to synthesize** - Once human input is provided, integrate with code-derived insights

### Example Interview Questions

**Row 1 (Planner):**

- What are the organization's strategic goals?
- How does this system support business objectives?
- What competitive advantages does this system provide?

**Row 2 (Owner):**

- What business processes does this system support?
- Who are the key stakeholders?
- What business rules govern this domain?

**Row 3 (Designer):**

- Why was this architecture pattern chosen?
- What alternatives were considered?
- What quality attributes were prioritized?

### Example Documents to Request

| Row | Documents |
| --- | --- |
| 1 | Strategic plan, business case, vision statement |
| 2 | Process maps, capability model, business requirements |
| 3 | ADRs, design documents, architecture guidelines |

## Implications for Plugin Use

### What the Plugin Does Well

- Technology inventory (Row 4-5)
- Code structure analysis (Row 4-5)
- Configuration audit (Row 5)
- Deployment analysis (Row 5-6)
- ADR management (Row 3-4, Column 6)

### What the Plugin Facilitates

- Structured data gathering (Rows 1-3)
- Interview guidance (Rows 1-2)
- Framework navigation (All rows)
- Gap identification (All rows)

### What Requires Human Input

- Strategic alignment (Row 1)
- Business process understanding (Row 2)
- Design rationale (Row 3)
- Runtime behavior (Row 6)

## Honest Reporting

All plugin output should clearly indicate:

1. **What was extracted from code** - High confidence
2. **What was inferred from structure** - Medium confidence
3. **What requires human input** - Cannot be determined from code
4. **What assumptions were made** - Should be verified

Example output format:

```markdown
## Zachman Analysis: Builder x What

### Code-Extracted (High Confidence)
- Data models found in /src/models/
- Database schema in /migrations/
- API types in /src/types/

### Inferred (Medium Confidence)
- Appears to follow domain-driven design
- Data seems to be event-sourced

### Requires Human Input
- Why this data model was chosen
- Business entity definitions
- Data ownership and governance

### Assumptions Made
- Assumed /src/models/ contains canonical data models
- Assumed migration files represent current schema
```

---

**Last Updated:** 2025-12-05
