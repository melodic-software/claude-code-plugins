# Enterprise Architecture Plugin

AI-assisted enterprise architecture guidance based on TOGAF, Zachman Framework, ADRs, and cloud alignment frameworks.

## Installation

```bash
/plugin install enterprise-architecture@claude-code-plugins
```

## Features

### Architecture Decision Records (ADRs)

The "killer app" of this plugin - document and manage architecture decisions.

```bash
# Create a new ADR
/ea:adr-create Use PostgreSQL for persistence

# Explain ADR concepts
/ea:explain ADR
```

### TOGAF Guidance

Get phase-specific guidance for TOGAF ADM (Architecture Development Method).

```bash
# Get guidance for a specific phase
/ea:togaf-phase A           # Architecture Vision
/ea:togaf-phase B           # Business Architecture
/ea:togaf-phase preliminary # Preliminary Phase
/ea:togaf-phase requirements # Requirements Management
```

### Zachman Framework Analysis

Analyze architecture from specific stakeholder perspectives.

```bash
# Analyze from builder perspective (what data structures)
/ea:zachman-analyze builder what

# Use wizard mode
/ea:zachman-analyze
```

### Architecture Documentation

Generate C4-style architecture documentation.

```bash
# Generate different document types
/ea:document context          # System context
/ea:document container        # Container architecture
/ea:document component        # Component details
/ea:document executive-summary # For leadership
```

### Architecture Review

Comprehensive review against principles and viewpoints.

```bash
# Review entire codebase
/ea:architecture-review

# Review staged changes
/ea:architecture-review staged

# Review specific files
/ea:architecture-review src/api/
```

### Dashboard

View architecture metrics and status.

```bash
/ea:dashboard
```

### Cloud Alignment

Check alignment with cloud frameworks.

```bash
# Use the cloud-alignment skill
/ea:explain cloud adoption framework
/ea:explain well-architected
```

## Skills Reference

| Skill | Purpose | Keywords |
| --- | --- | --- |
| `adr-management` | Create and manage ADRs | adr, decision, alternatives |
| `ea-learning` | Explain EA concepts | explain, what is, togaf, zachman |
| `architecture-documentation` | Generate docs with diagrams | document, c4, viewpoint |
| `togaf-guidance` | TOGAF ADM phase guidance | togaf, adm, phase |
| `zachman-analysis` | Zachman perspective analysis | zachman, viewpoint, perspective |
| `gap-analysis` | Current/target state analysis | gap, migration, roadmap |
| `cloud-alignment` | CAF/Well-Architected alignment | caf, well-architected, azure, aws |

## Agents Reference

| Agent | Purpose | Model |
| --- | --- | --- |
| `architecture-documenter` | Generate comprehensive docs | Sonnet |
| `viewpoint-analyzer` | Analyze stakeholder perspectives | Haiku |
| `principles-validator` | Validate against principles | Sonnet |
| `migration-explorer` | Explore migration options | Sonnet |

## Commands Reference

| Command | Purpose |
| --- | --- |
| `/ea:adr-create <title>` | Create new ADR |
| `/ea:explain <concept>` | Explain EA concept |
| `/ea:document <type>` | Generate architecture document |
| `/ea:togaf-phase <phase>` | Get TOGAF phase guidance |
| `/ea:zachman-analyze [row] [column]` | Analyze from Zachman perspective |
| `/ea:architecture-review [scope]` | Review architecture |
| `/ea:dashboard` | Show architecture metrics |

## Framework References

### TOGAF 10

The Open Group Architecture Framework provides methodology via the ADM:

- Preliminary Phase + Phases A-H
- Requirements Management (cross-cutting)
- Four domains: Business, Data, Application, Technology

### Zachman Framework 3.0

A 6x6 ontology for classifying architecture artifacts:

- Rows: Planner, Owner, Designer, Builder, Subcontractor, User
- Columns: What, How, Where, Who, When, Why

**Important:** Rows 1-3 require human input; rows 4-6 can be extracted from code.

### Microsoft Cloud Adoption Framework (CAF)

7 methodologies for Azure adoption:

- Strategy, Plan, Ready, Adopt, Govern, Secure, Manage

### AWS Well-Architected Framework

6 pillars for workload design:

- Operational Excellence, Security, Reliability
- Performance Efficiency, Cost Optimization, Sustainability

## Visualization Integration

This plugin integrates with the `visualization` plugin for C4 diagrams:

```bash
# Install visualization plugin (recommended)
/plugin install visualization@claude-code-plugins
```

When available, the `architecture-documenter` agent will generate Mermaid or PlantUML diagrams. Without it, text-based descriptions are provided.

## Repository Structure

The plugin expects architecture artifacts in `/architecture/`:

```text
/architecture/
  README.md
  principles.md
  /adr/
    0001-initial-architecture.md
    0002-database-selection.md
  /viewpoints/
    context.md
    containers.md
    /components/
```

See `memory/repository-structure.md` for full details.

## Configuration

### Architecture Compliance Hook

An optional hook checks file changes against architecture principles. Disabled by default.

Enable with environment variable:

```bash
export CLAUDE_HOOK_ARCHITECTURE_COMPLIANCE_ENABLED=true
```

This provides lightweight reminders. For comprehensive validation, use `/ea:architecture-review`.

## Honest Limitations

This plugin acknowledges what it can and cannot do:

### What It Does Well

- ADR creation and management
- Technology stack analysis (Zachman rows 4-5)
- TOGAF phase guidance
- Code-derived architecture documentation
- Technical gap analysis

### What Requires Human Input

- Business strategy (Zachman rows 1-2)
- Design rationale (without ADRs)
- Budget and timeline decisions
- Organizational context

All outputs clearly indicate what was extracted from code vs what requires human input.

## Memory Files

Reference documentation included:

- `adr-template.md` - Standard ADR format
- `repository-structure.md` - Directory structure guide
- `togaf-overview.md` - TOGAF 10 quick reference
- `zachman-overview.md` - Zachman 3.0 matrix
- `zachman-limitations.md` - Code extraction limits
- `architecture-principles.md` - Principles template
- `cloud-frameworks/caf-pillars.md` - Microsoft CAF
- `cloud-frameworks/well-architected.md` - AWS Well-Architected

## Contributing

This plugin is part of the claude-code-plugins repository. Contributions welcome!

## License

MIT
