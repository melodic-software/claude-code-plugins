---
description: Create a new Architecture Decision Record (ADR)
argument-hint: <title>
allowed-tools: Read, Write, Glob, Skill
---

# Create Architecture Decision Record

Create a new ADR documenting an architecture decision.

## Arguments

`$ARGUMENTS` - The title/topic of the architecture decision (e.g., "Use PostgreSQL for persistence")

## Workflow

1. **Invoke the adr-management skill** to access the ADR creation workflow
2. **Determine next ADR number** by scanning existing ADRs in `/architecture/adr/`
3. **Create the ADR file** using the standard template with:
   - Proper numbering (0001, 0002, etc.)
   - Initial status: "Proposed"
   - Current date
   - Title from arguments
4. **Report the created file path** so the user can edit it

## Example Usage

```bash
/ea:adr-create Use PostgreSQL for persistence
/ea:adr-create Adopt microservices architecture
/ea:adr-create Select React for frontend framework
```

## Output

Report:

- Created ADR file path
- ADR number assigned
- Reminder to fill in Context, Decision, and Consequences sections
