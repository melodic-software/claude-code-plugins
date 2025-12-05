# Lesson 12 Analysis: Multi-Agent Orchestration - The O-Agent

> **CRITICAL ARCHITECTURAL CONSTRAINT (Dec 2025)**
>
> **Subagents cannot spawn other subagents.** This prevents infinite nesting.
>
> **Impact on Orchestration Patterns:**
>
> - The orchestrator MUST be the main conversation thread, NOT a subagent
> - Use primary agents (full Claude Code instances via SDK) for multi-level orchestration
> - The patterns in this lesson require the Claude Agent SDK with custom MCP tools
> - This is a **backend service pattern**, not a Claude Code subagent pattern
>
> **Workaround:** Use MCP tools (`create_agent`, `command_agent`, `delete_agent`) with external database for agent state and WebSocket/HTTP for inter-agent communication.
>
> See: `code.claude.com/docs/en/sub-agents` (subagent limitations section)

## Content Summary

### Core Tactic

**Orchestrate to Scale** - Command your fleet of agents using the single interface pattern. The rate at which you create and command agents becomes your engineering output constraint. Build multi-agent orchestration with the O-Agent (Orchestrator Agent) to scale your compute to scale your impact.

### Key Frameworks

#### The Complete Agent Evolution Path

| Level | Name | Description |
| ----- | ---- | ----------- |
| 1 | Base Agents | Out-of-the-box agents |
| 2 | Better Agents | Prompt + context engineering |
| 3 | More Agents | Scaling with multiple agents |
| 4 | Custom Agents | Domain-specific solutions |
| 5 | **Orchestrated Agents** | Fleet management via single interface |

#### The Three Pillars of Multi-Agent Orchestration

| Pillar | Purpose | Key Benefit |
| ------ | ------- | ----------- |
| **Orchestrator Agent** | Unified interface | Single point of command |
| **CRUD for Agents** | Agent lifecycle management | Scale agent creation/deletion |
| **Observability** | Real-time monitoring | Measure to improve |

> "If you can't measure it, you can't improve it. If you can't measure it, you can't scale it."

#### The Single Interface Pattern

```text
User --> Orchestrator Agent --> Creates/Commands/Deletes Specialized Agents
                            --> Returns Results + Observability
```markdown

One agent to rule them all - talk to one orchestrator that:

- Creates specialized agents
- Commands them with detailed prompts
- Monitors their progress
- Aggregates their results
- Deletes them when work is done

#### PETER Framework for Multi-Agent Systems

Multi-agent orchestration is an out-loop PETER system:

| Element | Implementation |
| ------- | -------------- |
| **P**rompt | User prompt to orchestrator |
| **T**rigger | HTTP request to server |
| **E**nvironment | Local/cloud deployment |
| **R**eview | Observability interface |

### Implementation Patterns from Lesson

#### 1. Orchestrator Agent Configuration

```python
# Orchestrator is a CUSTOM agent specialized at managing other agents
options = ClaudeCodeOptions(
    system_prompt=load_orchestrator_prompt(),  # Complete override
    model="claude-4-sonnet",
    # Custom tools for agent management
    mcp_servers=[create_sdk_mcp_server(tools=[
        create_agent,
        command_agent,
        delete_agent,
        list_agents,
        check_agent_status,
        read_agent_logs
    ])]
)
```markdown

#### 2. Orchestrator Tools

| Tool | Purpose |
| ---- | ------- |
| `create_agent` | Spin up new primary agent |
| `command_agent` | Send prompt to agent |
| `delete_agent` | Clean up agent when done |
| `list_agents` | Get all active agents |
| `check_agent_status` | Monitor agent progress |
| `read_agent_logs` | View agent responses |

#### 3. Agent Templates for Orchestrator

```text
.claude/agents/
├── scout_fast.md      # Fast reconnaissance agent
├── builder.md         # Code modification agent
├── planner.md         # Planning agent
├── reviewer.md        # Review agent
└── qa_fast.md         # Quick QA agent
```markdown

Templates define:

- System prompt
- Model selection
- Allowed/disallowed tools
- Hook configurations

#### 4. Orchestration Workflow Pattern

```markdown
## Orchestration Workflow

### Phase 1: Plan with Scouts
1. Create scout agents
2. Command: Analyze codebase for task
3. Wait for completion
4. Aggregate findings

### Phase 2: Build
1. Create builder agent
2. Command: Implement based on scout reports
3. Monitor progress
4. Collect results

### Phase 3: Review
1. Create reviewer agent
2. Command: Verify implementation
3. Generate final report

### Final Report
[Structured output format]
```markdown

#### 5. Results-Oriented Engineering

Every agent must produce a concrete result:

```python
# Agent Response Structure
{
    "consumed_assets": ["file1.ts", "file2.ts"],  # Files read
    "produced_assets": ["docs/summary.md"],       # Files created/modified
    "summary": "Created architecture documentation",
    "status": "completed"
}
```markdown

#### 6. Context Protection via Delegation

```text
R&D Framework Applied:
- Reduce: Keep orchestrator context minimal
- Delegate: Let sub-agents handle actual work

Orchestrator Context:
- Agent management
- High-level orchestration
- Result aggregation

Sub-Agent Contexts:
- Actual codebase work
- Tool calls
- File operations
```markdown

### Multi-Agent Architecture

```text
Multi-Agent Orchestration System
├── Frontend (Vue/React)
│   ├── Prompt Input Interface
│   ├── Agent Cards (status, tools, context)
│   ├── Log Viewer (filter by agent/tool/type)
│   └── Result Inspector (consumed/produced assets)
├── Backend (FastAPI/Express)
│   ├── HTTP Endpoints (create, command, delete)
│   ├── WebSocket (real-time updates)
│   └── Orchestrator Service
│       ├── Claude SDK Client
│       └── Agent Management
└── Data Layer (Postgres)
    ├── Agents Table
    ├── Messages Table
    └── Results Table
```markdown

### Anti-Patterns Identified

- **Blind sub-agents**: Sub-agents lose context and can't be re-prompted
- **Orchestrator doing work**: Should only orchestrate, not perform tasks
- **Missing observability**: Can't scale what you can't measure
- **Keeping dead agents**: Delete agents when their job is done
- **Overloading orchestrator context**: Let specialized agents handle details
- **No result artifacts**: Every agent should produce concrete outputs

### Metrics/KPIs

Multi-agent orchestration success indicators:

- **Agents deployed per task**: Compute utilization
- **Context per agent**: Keeping contexts focused
- **Time to completion**: Multi-agent speedup
- **Result quality**: Observability enables improvement
- **Agent lifecycle**: Create -> Command -> Delete pattern

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `orchestrator-design` | Design O-Agent systems | orchestrator, fleet, multi-agent |
| `agent-lifecycle-management` | CRUD operations for agents | create, delete, command, monitor |
| `multi-agent-observability` | Build observability interfaces | logs, monitoring, results |
| `orchestration-prompts` | Write prompts for orchestrator | orchestration, workflow, phases |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `fleet-manager` | Manage agent fleet | Custom orchestrator tools |
| `scout-fast` | Quick codebase reconnaissance | Read, Glob, Grep |
| `builder` | Code implementation | Read, Write, Edit, Bash |
| `reviewer` | Code review and verification | Read, Glob, Grep |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/orchestrate` | Run orchestration workflow | `$ARGUMENTS` - task description |
| `/scout_and_build` | Scout then build pattern | `$ARGUMENTS` - feature description |
| `/deploy_team` | Create team of specialized agents | `$ARGUMENTS` - team composition |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `three-pillars.md` | Orchestrator + CRUD + Observability | When building multi-agent systems |
| `single-interface-pattern.md` | O-Agent architecture | When designing orchestrators |
| `agent-lifecycle.md` | Create -> Command -> Delete | When managing agent fleet |
| `results-oriented-engineering.md` | Concrete outputs from agents | When designing agent outputs |
| `peter-multi-agent.md` | PETER for orchestration | When building out-loop systems |

## Key Insights for Plugin Development

### High-Value Components from Lesson 12

1. **Memory File: `three-pillars.md`**
   - Orchestrator Agent
   - CRUD for Agents
   - Observability
   - Why all three are essential

2. **Memory File: `single-interface-pattern.md`**
   - One orchestrator to rule them all
   - Tool definitions for agent management
   - Context protection strategies

3. **Skill: `orchestrator-design`**
   - System prompt for orchestrators
   - Tool selection
   - Integration with agent templates

4. **Orchestration Workflow Template**
   - Phase-based execution
   - Scout -> Build -> Review pattern
   - Result aggregation

### Key Quotes

> "In the generative AI age, the rate at which you can create and command your agents becomes the constraint of your engineering output."
>
> "If you can't measure it, you can't improve it. If you can't measure it, you can't scale it."
>
> "You must treat your agents as deletable temporary resources that serve a single purpose."
>
> "Don't let these other agentic coding tools fool you. Claude Code and the Agent SDK and the ecosystem is far ahead of the pack."
>
> "The orchestrator agent is a custom agent specialized at solving the problem of managing other agents."
>
> "We have a powerful version of that [agentic layer] that works even before you get concrete ADWs inside your codebase."

### Orchestrator System Prompt Architecture

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

## Tool Usage
- `create_agent`: Spin up new agent with template
- `command_agent`: Send prompt to specific agent
- `check_agent_status`: Get agent progress
- `list_agents`: View all active agents
- `delete_agent`: Clean up completed agents

## Workflow Pattern
1. Analyze task requirements
2. Create appropriate agents
3. Command agents with detailed instructions
4. Monitor progress (sleep + check status)
5. Aggregate results
6. Report to user
7. Delete agents

## Context Protection
- Keep your context focused on orchestration
- Delegate detailed work to specialized agents
- Do not read files directly - have agents do it
- Do not write code - have builder agents do it
```markdown

### Future Directions

| Direction | Benefit |
| --------- | ------- |
| Human-in-loop decision points | Agent asks user questions |
| Agent forking | Duplicate agent at specific context state |
| ADW integration | Orchestrator calls AI Developer Workflows |
| Autocomplete/Tab | Fast model helps with prompt engineering |
| Multi-codebase | Single orchestrator across projects |

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 56:30 of content!)
- [x] Understood Three Pillars framework
- [x] Understood Single Interface Pattern
- [x] Understood O-Agent architecture
- [x] Understood PETER for multi-agent
- [x] Understood R&D framework at scale
- [x] Understood agent lifecycle management
- [x] Understood observability requirements
- [x] Explored multi-agent-orchestration repository (2025-12-04)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Culminates Lesson 1**: Stop coding -> orchestrate agents to code
- **Culminates Lesson 2**: 12 leverage points -> Core Four at scale
- **Culminates Lesson 4**: PITER -> PETER for multi-agent
- **Culminates Lesson 6**: One agent, one purpose -> focused fleet
- **Culminates Lesson 7**: ZTE -> delete agents when done
- **Culminates Lesson 8**: Agentic layer -> orchestration layer
- **Culminates Lesson 9**: R&D context -> protect orchestrator context
- **Culminates Lesson 10**: Agentic prompts -> orchestration prompts
- **Culminates Lesson 11**: Custom agents -> orchestrator is custom agent

## Notable Implementation Details

### Orchestrator Tool Definitions

```python
@tool(
    name="create_agent",
    description="Create a new specialized agent from template"
)
def create_agent(args: dict) -> dict:
    template = args.get("template")
    name = args.get("name")
    # Load template, create agent instance
    agent = AgentManager.create(template, name)
    return {"agent_id": agent.id, "status": "created"}

@tool(
    name="command_agent",
    description="Send a prompt to a specific agent"
)
def command_agent(args: dict) -> dict:
    agent_id = args.get("agent_id")
    prompt = args.get("prompt")
    # Get agent, send prompt
    response = AgentManager.command(agent_id, prompt)
    return {"status": "commanded", "response_preview": response[:500]}

@tool(
    name="delete_agent",
    description="Delete an agent when its work is complete"
)
def delete_agent(args: dict) -> dict:
    agent_id = args.get("agent_id")
    AgentManager.delete(agent_id)
    return {"status": "deleted", "agent_id": agent_id}
```markdown

### Observability Interface Pattern

```typescript
// Frontend Agent Card
interface AgentCard {
  id: string;
  name: string;
  status: "idle" | "running" | "completed" | "error";
  template: string;
  model: string;
  contextUsage: number;
  totalCost: number;
  messageCount: number;
  toolCallCount: number;
  consumedAssets: string[];
  producedAssets: string[];
}

// Log Entry
interface LogEntry {
  timestamp: Date;
  agentId: string;
  type: "response" | "tool_call" | "thinking" | "result";
  content: string;
  metadata: Record<string, any>;
}
```markdown

### Multi-Phase Orchestration Prompt

```markdown
# Scout and Build Workflow

## Phase 1: Scout
1. Create scout agents (use scout_fast template)
2. Command: Analyze [specific area] for [task]
3. Loop: Check status every 15 seconds
4. Report: Aggregate scout findings

## Phase 2: Build
1. Create builder agent (use builder template)
2. Command: Implement based on scout reports
   - Include all relevant findings
   - Specify exact files to modify
3. Loop: Check status
4. Report: List all changes made

## Phase 3: Review
1. Create reviewer agent
2. Command: Verify implementation
3. Report: Confirm or flag issues

## Final Report
- Total agents used: [count]
- Total cost: [sum]
- Files consumed: [list]
- Files produced: [list]
- Summary: [one paragraph]
```yaml

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
