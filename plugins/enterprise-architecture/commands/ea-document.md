---
description: Generate architecture document (context, container, component, deployment, data, executive-summary)
argument-hint: <type>
allowed-tools: Task, Read, Write, Glob, Grep, Skill
---

# Generate Architecture Document

Generate architecture documentation for the current codebase.

## Arguments

`$ARGUMENTS` - The document type to generate:

- `context` - System context (boundaries, external interactions)
- `container` - Container architecture (services, databases, major components)
- `component` - Component architecture (internal structure of a container)
- `deployment` - Deployment architecture (infrastructure, environments)
- `data` - Data architecture (data flows, storage, schemas)
- `executive-summary` - Executive summary (business value, key decisions)

## Workflow

1. **Spawn the architecture-documenter agent** with the document type
2. **The agent will**:
   - Analyze the codebase structure
   - Identify relevant components based on document type
   - Generate documentation using standard templates
   - Integrate C4 diagrams via visualization plugin (if available)
3. **Output the generated document** to `/architecture/viewpoints/`

## Example Usage

```bash
/ea:document context
/ea:document container
/ea:document component
/ea:document executive-summary
```

## Output

- Generated document saved to `/architecture/viewpoints/`
- Analysis scope report (what was analyzed vs skipped)
- Diagram integration status
