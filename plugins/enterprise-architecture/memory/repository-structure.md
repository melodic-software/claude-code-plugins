# Repository Structure for Architecture Documentation

Standard directory structure for architecture artifacts.

## Recommended Structure

```text
/architecture/
  README.md                    # Overview and navigation
  principles.md                # Architecture principles

  /adr/                        # Architecture Decision Records
    0001-initial-architecture.md
    0002-database-selection.md
    ...

  /viewpoints/                 # Architecture documentation
    context.md                 # C4 Context diagram + docs
    containers.md              # C4 Container diagram + docs
    /components/               # C4 Component diagrams per container
      api-gateway.md
      user-service.md
      ...
    deployment.md              # Deployment architecture
    data.md                    # Data architecture
    executive-summary.md       # High-level overview

  /diagrams/                   # Source files for diagrams
    /mermaid/
      context.mmd
      containers.mmd
    /plantuml/
      component-api.puml

  /transitions/                # Migration and transition plans
    transition-1-containerization.md
    transition-2-cloud-migration.md

  /standards/                  # Architecture standards
    api-guidelines.md
    security-standards.md
    coding-standards.md
```

## File Descriptions

### Root Files

| File | Purpose |
| --- | --- |
| `README.md` | Navigation and overview of architecture docs |
| `principles.md` | Architecture principles (see architecture-principles.md) |

### ADR Directory

- Sequential numbering (0001, 0002, etc.)
- One decision per file
- Immutable once accepted
- See `adr-template.md` for format

### Viewpoints Directory

Documents for different stakeholder perspectives:

| File | Audience | Content |
| --- | --- | --- |
| `context.md` | All stakeholders | System boundaries, external systems |
| `containers.md` | Technical leads | Services, databases, major components |
| `components/*.md` | Developers | Internal structure per container |
| `deployment.md` | Operations | Infrastructure, environments |
| `data.md` | Data architects | Data flows, storage, schemas |
| `executive-summary.md` | Leadership | Business value, key decisions |

### Diagrams Directory

Source files for diagrams:

- Keep source separate from rendered output
- Version control diagram sources
- Organize by tool (mermaid, plantuml)

### Transitions Directory

Migration and transition plans:

- Gap analysis results
- Migration options
- Implementation roadmaps

### Standards Directory

Technical standards and guidelines:

- API design guidelines
- Security requirements
- Coding standards

## Getting Started

If no `/architecture/` directory exists:

1. Create the directory structure
2. Start with `principles.md` (optional but recommended)
3. Create first ADR for any significant decision
4. Add viewpoint documents as needed

Minimum viable architecture documentation:

- `/architecture/adr/` - At least one ADR
- `/architecture/viewpoints/context.md` - System context

## Integration with Plugin

The enterprise-architecture plugin expects this structure:

- `/ea:adr-create` creates files in `/architecture/adr/`
- `/ea:document` creates files in `/architecture/viewpoints/`
- `/ea:dashboard` scans `/architecture/` for metrics
- `principles-validator` looks for `/architecture/principles.md`

---

**Last Updated:** 2025-12-05
