---
description: Show architecture overview and metrics (ADR count, documentation coverage, Zachman cell coverage)
allowed-tools: Read, Glob, Grep, Skill
---

# Enterprise Architecture Dashboard

Display architecture metrics and status overview for the current project.

## Workflow

1. **Scan architecture artifacts**:
   - Count ADRs in `/architecture/adr/`
   - Check ADR status distribution (proposed, accepted, deprecated, superseded)
   - Identify documentation in `/architecture/viewpoints/`
   - Check for architecture principles file

2. **Calculate coverage metrics**:
   - **ADR Coverage**: Number of decisions documented
   - **Documentation Coverage**: Which document types exist (context, container, component, etc.)
   - **Zachman Coverage**: Which cells have documentation

3. **Report status summary**:
   - Overall architecture health
   - Missing documentation recommendations
   - Recent ADR activity

## Output Format

```markdown
# Architecture Dashboard

## ADR Status
- Total: X ADRs
- Proposed: X | Accepted: X | Deprecated: X | Superseded: X
- Latest: [ADR title] (date)

## Documentation Coverage
- [x] Context diagram
- [ ] Container diagram
- [ ] Component diagrams
- [x] Executive summary
- [ ] Data architecture

## Zachman Coverage
         What  How   Where  Who   When  Why
Planner   [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
Owner     [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
Designer  [ ]   [ ]   [ ]   [ ]   [ ]   [ ]
Builder   [x]   [x]   [ ]   [ ]   [ ]   [x]
Subcontr  [x]   [ ]   [ ]   [ ]   [ ]   [ ]
User      [ ]   [ ]   [ ]   [ ]   [ ]   [ ]

## Recommendations
- Create container diagram for service overview
- Document data architecture
- Add ADR for [identified decision]
```

## Example Usage

```bash
/ea:dashboard
```
