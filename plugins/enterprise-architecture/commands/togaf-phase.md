---
description: Get guidance for TOGAF ADM phase (preliminary, A-H, requirements)
argument-hint: <phase>
allowed-tools: Read, Glob, Grep, Skill
---

# TOGAF ADM Phase Guidance

Get detailed guidance for a specific TOGAF ADM phase.

## Arguments

`$ARGUMENTS` - The ADM phase:

- `preliminary` - Establish architecture capability
- `A` or `vision` - Architecture Vision
- `B` or `business` - Business Architecture
- `C` or `information` - Information Systems Architecture (Data + Application)
- `D` or `technology` - Technology Architecture
- `E` or `opportunities` - Opportunities & Solutions
- `F` or `migration` - Migration Planning
- `G` or `governance` - Implementation Governance
- `H` or `change` - Architecture Change Management
- `requirements` - Requirements Management (cross-cutting)

## Workflow

1. **Invoke the togaf-guidance skill** with the phase argument
2. **Provide phase-specific guidance** including:
   - Phase purpose and objectives
   - Key activities
   - Expected deliverables
   - When you're in this phase
   - Connections to other phases

## Example Usage

```bash
/ea:togaf-phase preliminary
/ea:togaf-phase A
/ea:togaf-phase vision
/ea:togaf-phase B
/ea:togaf-phase requirements
```

## Output

Comprehensive guidance for the specified TOGAF ADM phase with practical advice on activities and deliverables.
