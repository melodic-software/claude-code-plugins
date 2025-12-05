---
description: Generate configuration for a team of specialized agents
---

# Deploy Team Command

Generate configuration and templates for deploying a team of specialized agents.

## Input

$ARGUMENTS - Team composition description (e.g., "2 scouts, 1 builder, 1 reviewer")

## Workflow

1. **Parse team composition** from arguments:
   - Count per agent type
   - Identify specialized requirements

2. **Generate agent configurations** for each team member:
   - Template selection or custom config
   - Model selection
   - Tool access
   - System prompt

3. **Design coordination pattern**:
   - Execution order (parallel vs sequential)
   - Data flow between agents
   - Aggregation points

4. **Output team deployment spec**:

```markdown
## Team Deployment Specification

**Team Composition:** [summary]

### Agent Configurations

#### Agent: scout_1
**Template:** scout-fast
**Model:** haiku
**Tools:** [Read, Glob, Grep]
**Purpose:** [specific purpose]

**System Prompt:**
```json

[customized prompt]

```

### Agent: scout_2

[configuration...]

### Agent: builder_1

[configuration...]

### Agent: reviewer_1

[configuration...]

### Coordination Pattern

**Execution Flow:**

```text

Phase 1 (Parallel):
  scout_1 --> findings_1
  scout_2 --> findings_2

Phase 2 (Sequential):
  Aggregate findings
  builder_1 --> implementation

Phase 3 (Sequential):
  reviewer_1 --> verification

```

**Data Flow:**

- scout outputs feed builder input
- builder output feeds reviewer input
- reviewer output becomes final report

### Observability Setup

**Metrics to Track:**

- [metric 1]
- [metric 2]

**Alerts:**

- [alert condition 1]
- [alert condition 2]

### SDK Implementation

**Required Components:**

- Claude Agent SDK
- MCP tools: [list]
- Database: [schema notes]

**Deployment Notes:**
[any special considerations]

```text

## Example

```

/deploy-team 3 scouts for API analysis, 2 builders for implementation, 1 reviewer

```text

## Team Templates

Common team compositions:

| Team | Composition | Use Case |
| ------ | ------------- | ---------- |
| Quick fix | 1 scout, 1 builder | Simple changes |
| Standard | 2 scouts, 1 builder, 1 reviewer | Normal features |
| Complex | 3+ scouts, 2 builders, 1 reviewer | Large changes |
| Research | 5 scouts | Exploration only |

## SDK Requirement

> **Important:** This command generates *specifications* for team deployment. Actual agent creation and management requires Claude Agent SDK with custom MCP tools.

## Cross-References

- @single-interface-pattern.md - Team management
- @agent-lifecycle-crud.md - Templates
- @orchestrator-design skill - Design workflow
- @agent-lifecycle-management skill - CRUD patterns
