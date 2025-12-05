# Three Pillars of Multi-Agent Orchestration

The essential framework for scaling agentic engineering through fleet management.

## The Three Pillars

| Pillar | Purpose | Key Benefit |
| -------- | --------- | ------------- |
| **Orchestrator Agent** | Unified interface | Single point of command |
| **CRUD for Agents** | Agent lifecycle management | Scale agent creation/deletion |
| **Observability** | Real-time monitoring | Measure to improve |

## Pillar 1: Orchestrator Agent

The orchestrator is a **custom agent specialized at managing other agents**.

### Key Characteristics

- **Single interface**: Talk to one agent that commands all others
- **No direct work**: Orchestrator delegates, never does tasks itself
- **Context protection**: Keep orchestrator context minimal
- **Tool-based management**: Uses tools to create/command/delete agents

### Orchestrator Role

```text
User --> Orchestrator --> Creates specialized agents
                      --> Commands agents with prompts
                      --> Monitors agent progress
                      --> Aggregates results
                      --> Deletes agents when done
```markdown

### What Orchestrator Does

- Interprets user intent
- Selects appropriate agent templates
- Creates specialized agents
- Crafts detailed prompts for agents
- Monitors execution progress
- Aggregates and reports results
- Cleans up completed agents

### What Orchestrator Does NOT Do

- Read files directly
- Write code
- Execute commands
- Make technical decisions
- Hold detailed context

## Pillar 2: CRUD for Agents

Agent lifecycle management at scale.

### The Operations

| Operation | Purpose | Tool |
| ----------- | --------- | ------ |
| **Create** | Spin up specialized agent | `create_agent` |
| **Read** | Check agent status | `list_agents`, `check_agent_status` |
| **Command** | Send prompts to agent | `command_agent` |
| **Delete** | Clean up when done | `delete_agent` |

### Lifecycle Pattern

```text
Create -> Command -> Monitor -> Aggregate -> Delete
   | | | | |
   v         v          v           v          v
Template  Prompt    Status     Results    Cleanup
```markdown

### Key Principle

> "Treat agents as deletable temporary resources that serve a single purpose."

- Create agents for specific tasks
- Command with detailed, focused prompts
- Monitor until completion
- Aggregate results
- Delete immediately when done
- Never keep dead agents

## Pillar 3: Observability

Real-time visibility into multi-agent execution.

### The Critical Quote

> "If you can't measure it, you can't improve it. If you can't measure it, you can't scale it."

### What to Observe

| Metric | Purpose |
| -------- | --------- |
| **Agent status** | Know what's running |
| **Context usage** | Monitor token consumption |
| **Costs** | Track spend per agent |
| **Tool calls** | See what agents are doing |
| **Results** | Verify outputs |
| **Time** | Measure execution duration |

### Observability Components

1. **Agent Cards**: Status, model, context, cost per agent
2. **Event Stream**: Real-time log of all activities
3. **Cost Tracking**: Per-agent and total costs
4. **Result Inspector**: consumed/produced assets
5. **Log Viewer**: Filterable activity history

## Why All Three Are Essential

### Missing Orchestrator

Without orchestrator:

- Manual agent management
- No unified interface
- Difficult coordination
- Context pollution

### Missing CRUD

Without lifecycle management:

- Can't scale agent creation
- No programmatic control
- Difficult cleanup
- Resource waste

### Missing Observability

Without observability:

- Flying blind
- Can't measure improvement
- Can't identify bottlenecks
- Can't scale confidently

## Integration Pattern

```text
┌─────────────────────────────────────────────┐
│              User Interface                  │
├─────────────────────────────────────────────┤
│                                             │
│   ┌───────────────────────────────────┐     │
│   │      Orchestrator Agent           │     │
│   │   (CRUD Tools + System Prompt)    │     │
│   └───────────────────────────────────┘     │
│                    │                        │
│         ┌─────────┼─────────┐               │
│         ▼         ▼         ▼               │
│     ┌─────┐   ┌─────┐   ┌─────┐            │
│     │Agent│   │Agent│   │Agent│            │
│     │  A  │   │  B  │   │  C  │            │
│     └─────┘   └─────┘   └─────┘            │
│         │         │         │               │
├─────────┴─────────┴─────────┴───────────────┤
│             Observability Layer              │
│   (Logs, Metrics, Events, Costs, Results)   │
└─────────────────────────────────────────────┘
```markdown

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
| -------------- | --------- | ---------- |
| Blind sub-agents | No visibility | Add observability |
| Orchestrator doing work | Context pollution | Delegate everything |
| Missing lifecycle | Dead agents accumulate | CRUD operations |
| No metrics | Can't improve | Track everything |
| Keeping completed agents | Resource waste | Delete when done |

## Cross-References

- @single-interface-pattern.md - O-Agent architecture
- @agent-lifecycle-crud.md - Lifecycle management
- @multi-agent-observability skill - Building observability
- @orchestrator-design skill - Designing orchestrators
