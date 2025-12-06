# TOGAF 10 Quick Reference

The Open Group Architecture Framework (TOGAF) provides a comprehensive methodology for developing enterprise architecture.

## Architecture Development Method (ADM)

TOGAF's core is the ADM - an iterative cycle of 10 phases.

### ADM Phases

| Phase | Name | Purpose |
| --- | --- | --- |
| Preliminary | - | Establish architecture capability, principles, governance |
| A | Architecture Vision | Create high-level vision, scope, stakeholders |
| B | Business Architecture | Define business strategy, processes, capabilities |
| C | Information Systems | Define data and application architectures |
| D | Technology Architecture | Define technology infrastructure and platforms |
| E | Opportunities & Solutions | Identify implementation approaches and projects |
| F | Migration Planning | Create detailed implementation roadmap |
| G | Implementation Governance | Oversee architecture implementation |
| H | Architecture Change Management | Guide ongoing architecture evolution |
| RM | Requirements Management | Manage requirements across all phases (cross-cutting) |

### Phase Flow

```text
            ┌─────────────────┐
            │   Preliminary   │
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │  A: Vision      │
            └────────┬────────┘
                     │
    ┌────────────────┼────────────────┐
    │                │                │
┌───▼───┐      ┌─────▼─────┐    ┌─────▼─────┐
│   B   │      │     C     │    │     D     │
│Business│      │Information│    │Technology │
└───┬───┘      └─────┬─────┘    └─────┬─────┘
    │                │                │
    └────────────────┼────────────────┘
                     │
            ┌────────▼────────┐
            │ E: Opportunities│
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │  F: Migration   │
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │ G: Governance   │
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │  H: Change Mgmt │
            └────────┬────────┘
                     │
            ┌────────▼────────┐
            │ Requirements    │◄── Cross-cutting
            │ Management      │    (all phases)
            └─────────────────┘
```

## Four Architecture Domains

| Domain | Focus | Key Artifacts |
| --- | --- | --- |
| Business | Processes, capabilities, organization | Capability maps, process models |
| Data | Information assets, data management | Data models, data flow diagrams |
| Application | Applications and interactions | Application portfolio, integration maps |
| Technology | Infrastructure and platforms | Technology standards, deployment diagrams |

## Key Concepts

### Enterprise Continuum

A classification scheme for architecture artifacts:

- **Foundation Architectures** - Generic, industry-wide
- **Common Systems Architectures** - Shared across organizations
- **Industry Architectures** - Specific to industry vertical
- **Organization-Specific Architectures** - Tailored to organization

### Architecture Repository

Where architecture artifacts are stored:

- Architecture Metamodel
- Architecture Capability
- Architecture Landscape
- Standards Information Base
- Reference Library
- Governance Log

### Building Blocks

Reusable components:

- **Architecture Building Blocks (ABBs)** - Logical components
- **Solution Building Blocks (SBBs)** - Physical implementations

## Practical Application

### Minimum Viable TOGAF

For smaller projects:

1. **Vision (A)** - What are we trying to achieve?
2. **Solution (C/D)** - What's the technical approach?
3. **Plan (F)** - How do we get there?
4. **Execute (G)** - Build it right

### Full Cycle

For enterprise initiatives:

- Complete all phases with appropriate rigor
- Formal stakeholder management
- Architecture review boards
- Governance checkpoints

## Phase Identification Guide

Not sure which phase you're in?

1. **Starting fresh with EA?** → Preliminary Phase
2. **Defining scope and getting buy-in?** → Phase A
3. **Understanding business needs?** → Phase B
4. **Designing systems and data?** → Phase C
5. **Selecting technologies?** → Phase D
6. **Identifying projects?** → Phase E
7. **Planning implementation?** → Phase F
8. **Overseeing execution?** → Phase G
9. **Maintaining/evolving?** → Phase H

## Related Resources

- togaf-guidance skill for detailed phase guidance
- `/ea:togaf-phase` command for phase-specific advice

---

**Last Updated:** 2025-12-05
