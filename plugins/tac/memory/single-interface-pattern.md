# Single Interface Pattern

One agent to rule them all - the O-Agent architecture.

## The Pattern

```text
User --> Orchestrator Agent --> Specialized Agents
                            --> Results + Observability
```markdown

**One interface to rule them all.** Talk to one orchestrator that:

- Creates specialized agents
- Commands them with detailed prompts
- Monitors their progress
- Aggregates their results
- Deletes them when done

## Why Single Interface?

### Benefits

| Benefit | Description |
| --------- | ------------- |
| **Unified command** | One place to issue all requests |
| **Abstraction** | User doesn't manage individual agents |
| **Coordination** | Orchestrator handles agent interaction |
| **Consistency** | Standard patterns across all work |
| **Scaling** | Add agents without changing interface |

### The Bottleneck Shift

> "In the generative AI age, the rate at which you can create and command your agents becomes the constraint of your engineering output."

Without orchestration:

- You manually create agents
- You manually coordinate work
- You manually aggregate results
- YOU are the bottleneck

With orchestration:

- Orchestrator creates agents
- Orchestrator coordinates work
- Orchestrator aggregates results
- AGENTS scale your output

## Orchestrator Architecture

### System Prompt Structure

```markdown
# Orchestrator Agent

## Purpose
Manage and coordinate specialized agents to accomplish complex tasks.
You do NOT perform work directly - you orchestrate other agents.

## Capabilities
- Create specialized agents from templates
- Command agents with detailed prompts
- Monitor agent progress
- Aggregate and report results
- Delete agents when work is complete

## Workflow Pattern
1. Analyze task requirements
2. Create appropriate agents
3. Command agents with detailed instructions
4. Monitor progress
5. Aggregate results
6. Report to user
7. Delete agents

## Context Protection
- Keep your context focused on orchestration
- Delegate detailed work to specialized agents
- Do not read files directly
- Do not write code
```markdown

### Management Tools

| Tool | Purpose | Parameters |
| ------ | --------- | ------------ |
| `create_agent` | Spin up new agent | template, name |
| `command_agent` | Send prompt to agent | agent_id, prompt |
| `check_agent_status` | Get agent progress | agent_id |
| `list_agents` | View all active agents | - |
| `delete_agent` | Clean up agent | agent_id |
| `read_agent_logs` | View agent responses | agent_id |

### Tool Usage Pattern

```text
Orchestrator receives task
    |
    v
create_agent(template="scout", name="scout_1")
    |
    v
command_agent(agent_id="scout_1", prompt="Analyze...")
    |
    v
Loop: check_agent_status(agent_id="scout_1")
    |
    v
Aggregate results from scout_1
    |
    v
create_agent(template="builder", name="builder_1")
    |
    v
command_agent(agent_id="builder_1", prompt="Implement based on scout report...")
    |
    v
Loop: check_agent_status(agent_id="builder_1")
    |
    v
delete_agent(agent_id="scout_1")
delete_agent(agent_id="builder_1")
    |
    v
Report final results to user
```markdown

## Context Protection

### R&D Framework Applied

**Reduce**: Keep orchestrator context minimal

- Only orchestration logic
- No file contents
- No code details
- No technical specifics

**Delegate**: Let sub-agents handle work

- Scouts read files
- Builders write code
- Reviewers analyze
- Each has focused context

### Context Boundaries

```text
Orchestrator Context:
├── Task understanding
├── Agent management
├── High-level progress
└── Result aggregation

Agent Contexts:
├── Scout: Codebase exploration
├── Builder: Implementation details
└── Reviewer: Code analysis
```markdown

## Agent Templates

### Template Structure

```yaml
---
name: template-name
description: What this agent does
tools: [Read, Write, Edit, etc.]
model: sonnet|haiku
---

# System Prompt

[Agent-specific instructions]
```markdown

### Common Templates

| Template | Purpose | Model |
| ---------- | --------- | ------- |
| `scout-fast` | Quick reconnaissance | Haiku |
| `builder` | Code implementation | Sonnet |
| `reviewer` | Code review | Sonnet |
| `planner` | Task planning | Sonnet |

## Implementation Note

> **SDK Constraint**: The orchestrator pattern requires Claude Agent SDK with custom MCP tools. Claude Code subagents cannot spawn other subagents.

Implementation paths:

- Claude Agent SDK + MCP servers
- Backend service architecture
- Database for agent state
- WebSocket for real-time updates

## Key Insights

> "The orchestrator agent is a custom agent specialized at solving the problem of managing other agents."

> "Don't let the orchestrator do direct work. It should only orchestrate."

> "Scale your compute by scaling your agents, not your time."

## Cross-References

- @three-pillars-orchestration.md - Full framework
- @agent-lifecycle-crud.md - Lifecycle operations
- @orchestrator-design skill - Design workflow
- @orchestration-prompts skill - Prompt patterns
