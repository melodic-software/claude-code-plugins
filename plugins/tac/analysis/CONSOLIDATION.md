# TAC Course Analysis - Consolidation

## Executive Summary

This document consolidates findings from all 12 lessons of the Tactical Agentic Coding (TAC) course into actionable plugin components.

**Core Philosophy:** Stop coding. Build systems that build systems. Your role shifts from implementer to commander of compute.

---

### SDK MIGRATION WARNING (Dec 2025)

The Claude Agent SDK has breaking changes since course recording:

| Change | Old Pattern | New Pattern |
| --- | --- | --- |
| Options class | `ClaudeCodeOptions` | `ClaudeAgentOptions` |
| System prompt loading | Automatic | Must explicitly set `system_prompt` |
| CLAUDE.md loading | Automatic | Must set `setting_sources=["project"]` |

See DOCUMENTATION_AUDIT.md for complete SDK import patterns and migration guidance.

### SDK LANGUAGE: TypeScript Recommended (Dec 2025)

Use **TypeScript SDK** (`@anthropic-ai/claude-agent-sdk`) for implementing TAC patterns:

- Full hook support (10/10 events vs Python's 6/10)
- Better type safety via Zod schemas
- Simpler single-function API

**Migration Required:** Course examples are Python - see porting patterns below.

| Python Pattern | TypeScript Equivalent |
| --- | --- |
| `@tool` decorator | `tool()` with Zod schemas |
| `ClaudeSDKClient` | `query()` async generator |
| `snake_case` options | `camelCase` options |
| `async with client:` | `for await (const msg of query())` |

See DOCUMENTATION_AUDIT.md Fifth Pass section for full comparison.

---

**The Eight Tactics:**

| # | Tactic | Core Idea |
| - | ------ | --------- |
| 1 | **Stop Coding** | Agents write code now |
| 2 | **Adopt Agent's Perspective** | 12 leverage points |
| 3 | **Template Your Engineering** | Meta-prompts and plans |
| 4 | **Stay Out The Loop** | PITER framework, AFK agents |
| 5 | **Always Add Feedback Loops** | Tests, validation, self-correction |
| 6 | **One Agent, One Purpose** | Specialized focused agents |
| 7 | **Target Zero-Touch Engineering** | Drop presence to 1, auto-ship |
| 8 | **Prioritize Agentics** | 50%+ time on agentic layer |

**Advanced Tactics (Lessons 9-12):**

| # | Tactic | Core Idea |
| - | ------ | --------- |
| 9 | **Master Context Engineering** | R&D framework, context layers |
| 10 | **Master Agentic Prompts** | Seven levels, stakeholder trifecta |
| 11 | **Build Custom Agents** | Claude Code SDK, domain-specific |
| 12 | **Orchestrate to Scale** | O-Agent, multi-agent systems |

---

## Key Frameworks Reference

### The Core Four (Foundation)

| Element | Description | Examples |
| ------- | ----------- | -------- |
| **Context** | What agent sees | CLAUDE.md, files, history |
| **Model** | Reasoning engine | Haiku, Sonnet, Opus |
| **Prompt** | Instructions | System prompt, user prompt |
| **Tools** | Capabilities | Read, Write, Bash, MCP |

### The 12 Leverage Points

**In-Agent (Core Four):**

1. Context, 2. Model, 3. Prompt, 4. Tools

**Through-Agent:**
5. Standard Out, 6. Types, 7. Documentation, 8. Tests, 9. Architecture, 10. Plans, 11. Templates, 12. ADWs

### The Agentic KPIs

| KPI | Direction | Target |
| --- | --------- | ------ |
| **Size** | UP | Larger work units |
| **Attempts** | DOWN | Target 1 |
| **Streak** | UP | Consecutive successes |
| **Presence** | DOWN | Target 1 (ZTE) |

### PITER Framework (Out-Loop)

| Element | Purpose | Implementation |
| ------- | ------- | -------------- |
| **P** | Prompt Input | GitHub Issues, Notion, etc. |
| **I** | (Implicit) | Issue classification |
| **T** | Trigger | Webhook, cron, manual |
| **E** | Environment | Dedicated device/sandbox |
| **R** | Review | PR review (or skip for ZTE) |

### PETER Framework (Multi-Agent)

| Element | Implementation |
| ------- | -------------- |
| **P** | User prompt to orchestrator |
| **T** | HTTP request to server |
| **E** | Local/cloud deployment |
| **R** | Observability interface |

### R&D Framework (Context)

| Element | Purpose | Implementation |
| ------- | ------- | -------------- |
| **R - Reduce** | Remove unnecessary context | Strip noise, irrelevant files |
| **D - Delegate** | Offload to specialized agents | Sub-agents for focused tasks |

### Seven Levels of Agentic Prompts

| Level | Name | Key Capability |
| ----- | ---- | -------------- |
| 1 | High Level | One-off repeatable tasks |
| 2 | Workflow | S-tier workflow section |
| 3 | Control Flow | If/else, loops, early returns |
| 4 | Delegation | Sub-agent orchestration |
| 5 | Higher Order | Prompts passing prompts |
| 6 | Template Meta | Prompts that generate prompts |
| 7 | Self-Improving | Self-modifying systems |

### Agent Evolution Path

| Level | Name | Description |
| ----- | ---- | ----------- |
| 1 | Base Agents | Out-of-the-box |
| 2 | Better Agents | Prompt + context engineering |
| 3 | More Agents | Scaling with multiple agents |
| 4 | Custom Agents | Domain-specific solutions |
| 5 | Orchestrated Agents | Fleet management via O-Agent |

### Three Pillars of Multi-Agent Orchestration

| Pillar | Purpose | Key Benefit |
| ------ | ------- | ----------- |
| **Orchestrator Agent** | Unified interface | Single point of command |
| **CRUD for Agents** | Agent lifecycle management | Scale agent creation/deletion |
| **Observability** | Real-time monitoring | Measure to improve |

---

## Plugin Component Specification

### Skills (Total: 28)

Skills provide workflow guidance and domain knowledge. Organized by lesson source.

#### Foundational (Lessons 1-4)

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `leverage-point-audit` | Audit codebase for 12 leverage point coverage | leverage, audit, agentic, improve |
| `standard-out-setup` | Add stdout logging to API endpoints | logging, stdout, errors, visibility |
| `template-engineering` | Guide creation of meta-prompt templates | template, meta-prompt, plan, encode |
| `plan-generation` | Assist in generating plans from templates | plan, spec, generate, specification |
| `adw-design` | Guide creation of AI Developer Workflows | ADW, workflow, automation, PITER |
| `afk-workflow-setup` | Set up PITER framework elements | PITER, prompt input, trigger, environment, AFK |
| `issue-classification` | Configure issue classification for ADWs | classify, chore, bug, feature |

#### Validation & Specialization (Lessons 5-7)

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `closed-loop-design` | Design closed loop prompts | closed loop, validate, feedback, test |
| `test-suite-setup` | Configure comprehensive test suites | test, pytest, ruff, typescript, playwright |
| `e2e-test-design` | Create end-to-end test scenarios | e2e, playwright, browser, user story |
| `agent-specialization` | Guide creation of focused agents | specialized, focus, one purpose, context |
| `review-workflow-design` | Design review workflows with proof | review, screenshot, spec, alignment |
| `conditional-docs` | Set up conditional documentation | documentation, conditional, context, when |
| `patch-design` | Create surgical patch workflows | patch, fix, minimal, targeted |
| `zero-touch-progression` | Guide progression from In-Loop to ZTE | ZTE, zero touch, out loop, presence |
| `git-worktree-setup` | Set up Git worktrees for parallelization | worktree, isolation, parallel, concurrent |
| `agentic-kpi-tracking` | Track and measure agentic coding KPIs | KPI, streak, attempts, presence, size |
| `composable-primitives` | Design composable agentic primitives | primitives, compose, SDLC, workflow |

#### Meta-Layer (Lessons 8-10)

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `agentic-layer-audit` | Audit codebase for agentic layer coverage | agentic layer, primitives, audit |
| `minimum-viable-agentic` | Guide creation of minimum viable agentic layer | MVP, minimum, agentic layer, start |
| `task-based-multiagent` | Set up task-based multi-agent systems | task, multi-agent, worktree, parallel |
| `notion-integration` | Configure Notion as prompt input source | notion, trigger, prompt input |
| `context-audit` | Audit current context composition | context, audit, tokens, window |
| `reduce-delegate-framework` | Apply R&D framework to prompts | reduce, delegate, context, optimize |
| `context-hierarchy-design` | Design memory hierarchy | CLAUDE.md, imports, hierarchy |
| `agent-expert-creation` | Create specialized agent experts | expert, specialized, domain, knowledge |
| `prompt-level-selection` | Guide selection of appropriate prompt level | prompt level, workflow, control flow |
| `prompt-section-design` | Design composable prompt sections | sections, variables, workflow, report |
| `template-meta-prompt-creation` | Create prompts that generate prompts | template, meta, generate, scaffold |
| `system-prompt-engineering` | Design effective system prompts | system prompt, custom agent, rules |

#### SDK & Orchestration (Lessons 11-12)

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `custom-agent-design` | Design custom agents from scratch | custom agent, SDK, system prompt, tools |
| `tool-design` | Create custom tools with @tool decorator | tool, decorator, MCP, in-memory |
| `agent-governance` | Implement hooks for permission control | hooks, governance, permission, block |
| `model-selection` | Choose appropriate model for task | haiku, sonnet, opus, model, cost |
| `orchestrator-design` | Design O-Agent systems | orchestrator, fleet, multi-agent |
| `agent-lifecycle-management` | CRUD operations for agents | create, delete, command, monitor |
| `multi-agent-observability` | Build observability interfaces | logs, monitoring, results |
| `orchestration-prompts` | Write prompts for orchestrator | orchestration, workflow, phases |

### Subagents (Total: 22)

Subagents are specialized agents with focused tool access.

#### Core SDLC Agents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `plan-generator` | Generate plans from templates | Read, Write, Glob, Grep |
| `plan-implementer` | Execute generated plans | Read, Write, Edit, Bash |
| `sdlc-planner` | Generate implementation plans from issues | Read, Write, Glob, Grep |
| `sdlc-implementer` | Implement plans with validation | Read, Write, Edit, Bash |
| `issue-classifier` | Classify issues into problem classes | Read |
| `branch-generator` | Generate semantic branch names | Read, Bash |
| `pr-creator` | Create well-formatted pull requests | Read, Bash |

#### Testing Agents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `test-runner` | Execute comprehensive test suites | Read, Bash, Glob |
| `e2e-test-runner` | Run Playwright browser tests | Read, Bash, MCP (Playwright) |
| `test-resolver` | Fix specific failing tests | Read, Write, Edit, Bash |
| `e2e-test-resolver` | Fix failing E2E tests | Read, Write, Edit, Bash, MCP |

#### Review & Documentation Agents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `spec-reviewer` | Review implementation against spec | Read, Bash, MCP (Playwright) |
| `patch-planner` | Create minimal patch plans | Read, Write, Glob |
| `patch-implementer` | Execute patch plans | Read, Write, Edit, Bash |
| `documentation-generator` | Generate and update docs | Read, Write, Glob, Grep |
| `conditional-docs-updater` | Update conditional documentation | Read, Edit |

#### Infrastructure Agents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `gateway-script-runner` | Execute ad-hoc prompts | Read, Write, Bash |
| `task-executor` | Execute tasks from task file | Read, Write, Bash, Glob |
| `prototype-generator` | Generate full prototypes from prompts | Read, Write, Bash, Edit |
| `shipper` | Validate state and merge to main | Read, Bash (git) |
| `worktree-installer` | Set up isolated worktree environments | Read, Write, Bash |
| `kpi-tracker` | Calculate and update agentic KPIs | Read, Write, Bash |

#### Prompt & Context Agents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `context-analyzer` | Analyze context composition | Read, Bash (/context) |
| `context-optimizer` | Suggest context reductions | Read, Write |
| `prompt-analyzer` | Analyze and improve existing prompts | Read, Glob, Grep |
| `prompt-generator` | Generate prompts from specifications | Read, Write |
| `workflow-designer` | Design workflow sections | Read, Write |

#### Custom Agent & Orchestration Agents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `agent-builder` | Build custom agent configurations | Read, Write, Bash |
| `tool-scaffolder` | Generate custom tool boilerplate | Read, Write |
| `hook-designer` | Design permission hooks | Read, Write, Glob |
| `fleet-manager` | Manage agent fleet | Custom orchestrator tools |
| `scout-fast` | Quick codebase reconnaissance | Read, Glob, Grep |
| `builder` | Code implementation | Read, Write, Edit, Bash |
| `reviewer` | Code review and verification | Read, Glob, Grep |

### Commands (Total: 35)

Commands are slash commands for common operations.

#### Context & Setup

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/prime` | Prime agent with codebase context | None |
| `/tools` | List available tools | None |
| `/install_worktree` | Set up isolated worktree environment | `$1` path, `$2` be_port, `$3` fe_port |

#### Planning (Meta-Prompts)

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/chore` | Generate chore plan from template | `$ARGUMENTS` - chore description |
| `/bug` | Generate bug fix plan from template | `$ARGUMENTS` - bug description |
| `/feature` | Generate feature plan from template | `$ARGUMENTS` - feature description |
| `/implement` | Execute a generated plan (HOP) | `$ARGUMENTS` - path to plan file |

#### Issue & Git Operations

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/classify-issue` | Classify GitHub issue type | `$ARGUMENTS` - issue JSON |
| `/generate_branch_name` | Generate branch name | `$1` type, `$2` adw_id, `$3` issue JSON |
| `/commit` | Create formatted commit | `$1` agent, `$2` type, `$3` issue JSON |
| `/pull_request` | Create PR with context | `$1` branch, `$2` issue, `$3` plan, `$4` adw_id |
| `/find_plan_file` | Find generated plan file | `$ARGUMENTS` - agent output |

#### Testing

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/test` | Run comprehensive test suite | None |
| `/test_e2e` | Run E2E tests with Playwright | `$1` adw_id, `$2` agent, `$3` test_file, `$4` url |
| `/resolve_failed_test` | Fix specific failing test | `$ARGUMENTS` - test failure JSON |
| `/resolve_failed_e2e_test` | Fix failing E2E test | `$ARGUMENTS` - E2E failure JSON |

#### Review & Documentation

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/review` | Review implementation against spec | `$1` spec file, `$2` adw_id, `$3` agent_name |
| `/patch` | Create minimal targeted fix | `$ARGUMENTS` - issue description |
| `/document` | Generate feature documentation | `$1` adw_id, `$2` agent_name |
| `/conditional_docs` | Load relevant documentation | Context-dependent |

#### KPIs & Tracking

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/track_agentic_kpis` | Update KPI tracking tables | `$ARGUMENTS` - state JSON |
| `/cleanup_worktrees` | Clean up stale worktrees | None |
| `/in_loop_review` | Human-in-loop review for validation | `$1` branch |

#### Prompt Engineering

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/prompt` | Run ad-hoc prompt from CLI | `$ARGUMENTS` - the prompt |
| `/slash_command` | Execute a slash command programmatically | `$1` - command name |
| `/create_prompt` | Generate a new prompt in specified format | `$ARGUMENTS` - description |
| `/team_prompt` | Create team-compatible prompt | `$ARGUMENTS` - prompt description |

#### Custom Agents

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/create_agent` | Scaffold a new custom agent | `$1` agent_name, `$2` purpose |
| `/create_tool` | Generate custom tool with decorator | `$1` tool_name, `$2` description |
| `/list_agent_tools` | List available tools for agent | None |

#### Orchestration

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/orchestrate` | Run orchestration workflow | `$ARGUMENTS` - task description |
| `/scout-and-build` | Scout then build pattern | `$ARGUMENTS` - feature description |
| `/deploy_team` | Create team of specialized agents | `$ARGUMENTS` - team composition |

### Memory Files (Total: 45)

Memory files are loaded into agent context via CLAUDE.md imports.

#### Core Philosophy

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `core-four-principles.md` | Context, Model, Prompt, Tools | Always - foundational |
| `agentic-coding-mindset.md` | Phase 2: stop coding, build systems | Always - mindset |
| `programmable-claude-patterns.md` | Running Claude Code programmatically | When building automation |

#### Leverage Points & KPIs

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `12-leverage-points.md` | Complete leverage point reference | When improving agentic coding |
| `agentic-kpis.md` | KPI definitions and measurement | When measuring success |
| `agent-perspective-checklist.md` | Questions from agent's view | Before starting agentic tasks |

#### Templates & Planning

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `template-engineering.md` | Template creation best practices | When creating templates |
| `meta-prompt-patterns.md` | Meta-prompt and HOP patterns | When building prompt hierarchies |
| `plan-format-guide.md` | Standard plan format sections | When generating/reviewing plans |
| `fresh-agent-rationale.md` | Why and when to use fresh instances | When deciding agent lifecycle |

#### PITER & ADWs

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `piter-framework.md` | PITER framework reference | When setting up AFK agents |
| `adw-anatomy.md` | ADW structure and patterns | When building workflows |
| `outloop-checklist.md` | Checklist for outloop systems | Before deploying ADWs |
| `agentic-layer.md` | Agentic layer architecture | When designing agent systems |

#### Testing & Validation

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `closed-loop-anatomy.md` | Request-Validate-Resolve structure | When designing validation |
| `test-leverage-point.md` | Why testing multiplies agent value | When explaining testing |
| `validation-commands.md` | Standard validation command reference | When adding tests to templates |
| `e2e-test-patterns.md` | E2E test structure and user stories | When creating browser tests |

#### Specialization & Review

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `one-agent-one-purpose.md` | Agent specialization principles | When designing agents |
| `review-vs-test.md` | Distinction between test and review | When setting up validation |
| `minimum-context-principle.md` | Context engineering guidance | When writing prompts |
| `conditional-docs-pattern.md` | How to set up conditional loading | When creating documentation |
| `proof-of-value.md` | Screenshot/artifact patterns | When implementing review |

#### ZTE & Infrastructure

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `zte-progression.md` | Three levels of agentic coding | When discussing scale/velocity |
| `git-worktree-patterns.md` | Worktree setup and isolation | When parallelizing agents |
| `composable-primitives.md` | The secret of agentic coding | When designing workflows |
| `belief-change-required.md` | Mindset shift required for ZTE | When introducing ZTE |

#### Agentic Layer

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `agentic-layer-structure.md` | Min viable vs scaled structures | When setting up agentic layer |
| `primitives-reference.md` | Complete primitives catalog | When composing workflows |
| `gateway-script-patterns.md` | Entry point script patterns | When starting agentic coding |
| `the-guiding-question.md` | Daily decision framework | Always (meta-tactic) |

#### Context Engineering

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `rd-framework.md` | R&D framework reference | When optimizing context |
| `context-layers.md` | Understanding context composition | When debugging context |
| `agent-expert-patterns.md` | Pre-loaded domain experts | When building specialized agents |

#### Prompt Engineering

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `seven-levels.md` | Prompt level reference and selection | When creating prompts |
| `prompt-sections-reference.md` | All composable sections | When designing prompts |
| `stakeholder-trifecta.md` | You, Team, Agents communication | When writing for team/agents |
| `system-vs-user-prompts.md` | Distinction and best practices | When building custom agents |
| `template-meta-patterns.md` | Meta-prompt examples | When creating prompt generators |

#### Custom Agents

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `agent-evolution-path.md` | Base -> Better -> More -> Custom | When planning agent strategy |
| `core-four-custom.md` | Controlling Core Four in custom agents | When building custom agents |
| `system-prompt-architecture.md` | Override vs append patterns | When configuring system prompts |
| `custom-tool-patterns.md` | @tool decorator and MCP patterns | When creating tools |
| `agent-deployment-forms.md` | Scripts, UIs, streams, terminals | When deploying agents |

#### Multi-Agent Orchestration

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `three-pillars.md` | Orchestrator + CRUD + Observability | When building multi-agent |
| `single-interface-pattern.md` | O-Agent architecture | When designing orchestrators |
| `agent-lifecycle.md` | Create -> Command -> Delete | When managing agent fleet |
| `results-oriented-engineering.md` | Concrete outputs from agents | When designing agent outputs |
| `peter-multi-agent.md` | PETER for orchestration | When building out-loop systems |

---

## Key Implementation Patterns

### Prompt Structure Template

```markdown
---
description: Brief description for team
model: sonnet
allowed-tools: Read, Write, Bash
---

# Title (direct, clear)

## Purpose
[1-2 sentences, direct language to agent]

## Variables
- `$ARGUMENTS` - Description of dynamic input
- `static_var: value` - Description of static value

## Workflow
1. First step
   - Detail if needed
2. Second step
3. If condition, early return
4. Continue processing

## Report
[Output format specification]
```markdown

### Closed Loop Pattern

```markdown
## Request
[What needs to be done]

## Validate
[How to verify success - commands to run]

## Resolve
[What to do if validation fails]
```markdown

### ADW Script Pattern

```python
#!/usr/bin/env -S uv run --script
from agent import prompt_claude_code, AgentPromptRequest

def main(prompt: str, model: str = "sonnet"):
    request = AgentPromptRequest(
        prompt=prompt,
        model=model,
        agent_name="oneoff"
    )
    response = prompt_claude_code(request)
    # Process and display response
```markdown

### Custom Agent Pattern

```python
# NOTE: Verify imports against official Claude Agent SDK documentation
from claude_agent_sdk import ClaudeAgentOptions, query, create_sdk_mcp_server

# [Editor's Note: Current model IDs as of Dec 2025:
#  - claude-opus-4-5-20251101 (Opus 4.5)
#  - claude-sonnet-4-5-20250929 (Sonnet 4.5)
#  - claude-haiku-4-5-20251001 (Haiku 4.5)]
options = ClaudeAgentOptions(
    model="claude-sonnet-4-5-20250929",  # Updated from course's "claude-sonnet-4-20250514"
    system_prompt=load_system_prompt("prompts/custom.md"),
    allowed_tools=["Read", "Write", "Bash"],
    disallowed_tools=["WebFetch"],
    mcp_servers={"custom": create_sdk_mcp_server(name="custom", version="1.0.0", tools=[custom_tool])},
    hooks={
        "pre_tool_use": [permission_hook]
    }
)

response = query(prompt, options=options)
```markdown

### Orchestrator Tool Pattern

```python
@tool(name="create_agent", description="Create a new specialized agent")
def create_agent(args: dict) -> dict:
    template = args.get("template")
    name = args.get("name")
    agent = AgentManager.create(template, name)
    return {"agent_id": agent.id, "status": "created"}

@tool(name="command_agent", description="Send prompt to agent")
def command_agent(args: dict) -> dict:
    agent_id = args.get("agent_id")
    prompt = args.get("prompt")
    response = AgentManager.command(agent_id, prompt)
    return {"status": "commanded", "response": response[:500]}

@tool(name="delete_agent", description="Delete agent when done")
def delete_agent(args: dict) -> dict:
    agent_id = args.get("agent_id")
    AgentManager.delete(agent_id)
    return {"status": "deleted"}
```yaml

---

## Key Quotes Reference

> "Your agent is brilliant, but blind."
>
> "The prompt is now the fundamental unit of engineering."
>
> "If you're not writing tests, you're probably vibe coding."
>
> "Context is the most important leverage point of agentic coding."
>
> "One well-crafted prompt can generate tens to hundreds of hours of productive work."
>
> "When you override the system prompt, this is NOT Claude Code anymore."
>
> "In the generative AI age, the rate at which you can create and command your agents becomes the constraint of your engineering output."
>
> "If you can't measure it, you can't improve it. If you can't measure it, you can't scale it."
>
> "The irreplaceable engineer of the future is not writing a single line of code."

---

## Anti-Patterns Summary

| Anti-Pattern | Why It's Bad | Alternative |
| ------------ | ------------ | ----------- |
| Vibe coding | No leverage | Template engineering |
| Context stuffing | Overloaded agents | R&D framework |
| Single agent for SDLC | Context exhaustion | Specialized agents |
| Missing feedback loops | No self-correction | Closed loop prompts |
| In-loop babysitting | Wasted time | Out-loop/ZTE |
| Manual review bottleneck | Slows velocity | ZTE progression |
| Competing with Claude Code | Won't win | Custom domain agents |
| Tool overload | Context waste | Focused tool sets |
| Novel format every time | Confusion | Consistent templates |
| Keeping dead agents | Resource waste | Delete when done |

---

## Validation Status

- [x] All 12 lessons analyzed
- [x] Components extracted and consolidated
- [x] Validated against official Claude Code docs (2025-12-04) - See DOCUMENTATION_AUDIT.md
- [x] Third pass validation complete (2025-12-04):
  - [x] All companion repos explored (lessons 1-12)
  - [x] SDK breaking changes documented (ClaudeCodeOptions -> ClaudeAgentOptions)
  - [x] Model ID corrections added (Editor's Notes)
  - [x] Command naming audit complete (20 commands need underscore->kebab-case)
  - [x] Subagent limitation documented (cannot spawn other subagents)
- [ ] Create actual plugin structure
- [ ] Write skill YAML frontmatter
- [ ] Write subagent configurations
- [ ] Write command templates
- [ ] Write memory file content
- [ ] Document SOP for future analysis runs

---

## Implementation Constraints (Fifth Pass - 2025-12-04)

This section consolidates all critical constraints identified during the fifth pass validation against official Claude Code documentation. These MUST be followed during plugin implementation.

### 1. CRITICAL: Subagent Spawning Limitation

**Official documentation states:** "Subagents cannot spawn other subagents" - This prevents infinite nesting.

**Impact:**

- Orchestrator/fleet patterns MUST run from main conversation thread
- Subagent files (`.claude/agents/*.md`) cannot delegate to other subagents
- Use primary agents (full Claude Code instances via SDK) for multi-level orchestration

**Workaround:**

- Use Claude Agent SDK with custom MCP tools (`create_agent`, `command_agent`, `delete_agent`)
- External database for agent state
- WebSocket/HTTP for inter-agent communication
- This is a **backend service pattern**, not a Claude Code subagent pattern

### 2. HIGH: SDK Class Naming

**Breaking change (v0.1.0):**

- `ClaudeCodeOptions` -> `ClaudeAgentOptions`
- TypeScript: `@anthropic-ai/claude-code` -> `@anthropic-ai/claude-agent-sdk`
- Python: `claude-code-sdk` -> `claude-agent-sdk`

### 3. MEDIUM: Model ID Currency

**Use aliases (preferred):** `sonnet`, `opus`, `haiku`

**Current full IDs (Dec 2025):**

- `claude-opus-4-5-20251101`
- `claude-sonnet-4-5-20250929`
- `claude-haiku-4-5-20251001`

### 4. MEDIUM: Skill Description Voice

**Official requirement:** Descriptions MUST use third person only.

- Good: "Processes files and generates reports"
- Bad: "I can help you process files"

### 5. LOW: Command Naming Convention

**Official standard:** kebab-case (e.g., `security-review.md`)

20 commands from TAC course use underscores and need conversion during implementation.

---

## Architecture Notes and TODOs

### CRITICAL: Orchestrator Subagent Limitation

**Official documentation states:** "subagents cannot spawn other subagents"

This impacts the proposed `orchestrator-agent` and `fleet-manager` components. These cannot work as designed because subagents cannot launch other subagents.

**Decision (Fourth Pass - 2025-12-04):** SDK-ONLY PATTERNS

These components are documented as **Claude Agent SDK patterns only**, not implementable as Claude Code subagents:

| Agent | Status | SDK Implementation |
| --- | --- | --- |
| `orchestrator-agent` | SDK-ONLY | Use MCP tools (`create_agent`, `command_agent`, `delete_agent`) |
| `fleet-manager` | SDK-ONLY | Use database-backed agent lifecycle management |

**Reference Implementation:** Lesson 12's `multi-agent-orchestration` repository demonstrates the correct architecture:

- Orchestrator uses custom MCP tools for agent management
- Agents tracked in PostgreSQL database
- WebSocket for real-time observability
- FastAPI backend + Vue frontend
- This is a Claude Agent SDK pattern, NOT a Claude Code subagent pattern

For users who want multi-agent orchestration within Claude Code:

- Use the main agent to invoke subagents sequentially
- Use skills to provide orchestration guidance
- Cannot have a subagent that spawns other subagents

### Built-in Agent Overlap

The following proposed agents may overlap with built-in Claude Code agents:

| Proposed | Built-in | Recommendation |
| --- | --- | --- |
| `planner-agent` / `sdlc-planner` | Plan subagent | Evaluate if built-in meets needs |
| `scout-fast` | Explore subagent | Evaluate if built-in meets needs |

### Components Reclassified

Based on audit, these should be memory files instead of skills:

- `context-optimizer` - Provides guidance, not task execution
- `prompt-designer` - Provides domain expertise, not file creation

---

**Consolidation Date:** 2025-12-04
**Consolidated By:** Claude Code (claude-opus-4-5-20251101)
**Documentation Audit:** 2025-12-04 - See DOCUMENTATION_AUDIT.md
**Third Pass Validation:** 2025-12-04 - All companion repos explored, SDK changes documented
**Fourth Pass Validation:** 2025-12-04 - Lesson 6 completed, SDK-only patterns confirmed, fresh docs audit
**Fifth Pass Validation:** 2025-12-04 - Implementation Constraints section added, critical corrections applied
