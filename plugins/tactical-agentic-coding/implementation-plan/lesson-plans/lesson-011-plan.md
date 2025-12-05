# TAC Plugin Lesson 011 Implementation Plan

## Summary

Implement Lesson 011 "Building Domain-Specific Agents" for the tactical-agentic-coding plugin. This lesson covers Claude Agent SDK patterns for custom agent creation, focusing on SDK architecture, custom tools, session management, and governance patterns.

## Source Material Validated

- [x] Lesson content at `plugins/tactical-agentic-coding/lessons/lesson-011-building-domain-specific-agents/`
- [x] Analysis at `plugins/tactical-agentic-coding/analysis/lesson-011-analysis.md`
- [x] Companion repo at `D:\repos\gh\disler\building-specialized-agents`
- [x] Official Claude Code SDK docs validated

## Core Concepts

### Agent Evolution Path

| Level | Name | Description |
| ------- | ------ | ------------- |
| 1 | Base Agents | Out-of-the-box agents (Claude Code, Codex CLI) |
| 2 | Better Agents | Prompt engineering + context engineering |
| 3 | More Agents | Scaling compute with multiple agents |
| 4 | Custom Agents | Domain-specific solutions with full SDK control |

### The Mismatch Problem

> "Out-of-the-box agents are built for everyone's codebase, not yours. This mismatch costs hundreds of hours and millions of tokens."

### Core Four at Scale

| Element | Out-of-Box | Custom Agent |
| --------- | ------------ | -------------- |
| Context | Generic CLAUDE.md | Domain-specific system prompt |
| Model | Default (Sonnet) | Task-appropriate (Haiku/Sonnet/Opus) |
| Prompt | User prompts only | Full system prompt control |
| Tools | 15+ default tools | Precise tool set (disallow unused) |

## Components to Create

### Memory Files (5 files)

Location: `plugins/tactical-agentic-coding/memory/`

| File | Purpose | Priority |
| ------ | --------- | ---------- |
| `agent-evolution-path.md` | Base -> Better -> More -> Custom progression | P1 |
| `core-four-custom.md` | Controlling Core Four in custom agents | P1 |
| `system-prompt-architecture.md` | Override vs append patterns | P1 |
| `custom-tool-patterns.md` | @tool decorator and MCP server patterns | P2 |
| `agent-deployment-forms.md` | Scripts, UIs, streams, terminals | P2 |

### Skills (4 skills)

Location: `plugins/tactical-agentic-coding/skills/`

| Skill | Purpose | Tags |
| ------- | --------- | ------ |
| `custom-agent-design` | Design custom agents from scratch | SDK, system-prompt, tools, domain |
| `tool-design` | Create custom tools with @tool decorator | tool, decorator, MCP, in-memory |
| `agent-governance` | Implement hooks for permission control | hooks, governance, permission, security |
| `model-selection` | Choose appropriate model for task | haiku, sonnet, opus, cost, performance |

### Commands (3 commands)

Location: `plugins/tactical-agentic-coding/commands/`

| Command | Purpose | Arguments |
| --------- | --------- | ----------- |
| `create-agent` | Scaffold a new custom agent | `$1` agent_name, `$2` purpose |
| `create-tool` | Generate custom tool boilerplate | `$1` tool_name, `$2` description |
| `list-agent-tools` | List available tools for agent configuration | None |

### Agents (3 agents)

Location: `plugins/tactical-agentic-coding/agents/`

| Agent | Purpose | Model | Tools |
| ------- | --------- | ------- | ------- |
| `agent-builder` | Build custom agent configurations | sonnet | Read, Write, Bash |
| `tool-scaffolder` | Generate custom tool boilerplate | haiku | Read, Write |
| `hook-designer` | Design permission hooks for governance | sonnet | Read, Write, Glob |

## Implementation Order

1. Create memory files (foundation knowledge)
2. Create skills (workflows for agent design)
3. Create commands (user-facing operations)
4. Create agents (automation)
5. Update MASTER-TRACKER

## Memory File Content Specifications

### 1. agent-evolution-path.md

**Source**: Lesson 011 transcript, analysis

**Content outline**:

- The four levels: Base -> Better -> More -> Custom
- When each level is appropriate
- Signs you need to move to next level
- The mismatch problem
- Domain-specific alpha
- "All the alpha is in hard specific problems"

### 2. core-four-custom.md

**Source**: Lesson 011 - Core Four at Scale

**Content outline**:

- Context control: system_prompt override vs append_system_prompt
- Model selection: Haiku for simple, Sonnet for balanced, Opus for complex
- Prompt control: Full system prompt vs user prompt only
- Tools control: allowed_tools, disallowed_tools patterns
- Token overhead warning: 15+ default tools consume context
- /context command to understand agent overhead

### 3. system-prompt-architecture.md

**Source**: Lesson 011 - System prompt patterns

**Content outline**:

- Override pattern: `system_prompt=...` - Creates new product
- Append pattern: `append_system_prompt=...` - Extends Claude Code
- When to use each approach
- Warning: Override = NOT Claude Code anymore
- Version control for system prompts
- External markdown file pattern

### 4. custom-tool-patterns.md

**Source**: Lesson 011 - @tool decorator patterns

**Content outline**:

- @tool decorator syntax
- create_sdk_mcp_server() for in-memory servers
- Tool naming: `mcp__<server>__<tool>`
- Return format: {"content": [{"type": "text", "text": ...}]}
- Error handling: is_error flag
- Must use ClaudeSDKClient (not query()) for custom tools
- Parameter type hints

### 5. agent-deployment-forms.md

**Source**: Lesson 011 - Deploy agents everywhere

**Content outline**:

- Script deployment (ADWs, automation)
- Terminal UI (interactive REPL)
- Backend API (UI integration)
- Data stream processing (real-time)
- Multi-agent orchestration
- Session resumption pattern
- Cost tracking pattern

## Skill Specifications

### 1. custom-agent-design

**Purpose**: Design custom agents from scratch using SDK patterns

**Workflow**:

1. Define agent purpose and domain
2. Select appropriate model
3. Design system prompt (override vs append)
4. Configure tool access (allowed/disallowed)
5. Add governance hooks if needed
6. Create deployment wrapper

### 2. tool-design

**Purpose**: Create custom tools with @tool decorator

**Workflow**:

1. Define tool name and description
2. Specify parameter schema
3. Implement tool logic
4. Add error handling
5. Create MCP server
6. Configure tool access in agent

### 3. agent-governance

**Purpose**: Implement hooks for permission control

**Workflow**:

1. Identify security requirements
2. Design hook matchers
3. Implement hook functions
4. Configure permission decisions
5. Add logging/auditing
6. Test with blocked scenarios

### 4. model-selection

**Purpose**: Choose appropriate model for task

**Decision tree**:

- Simple transformations -> Haiku
- Balanced performance -> Sonnet
- Complex reasoning -> Opus
- Cost-sensitive -> Haiku
- Quality-critical -> Opus

## Validation Criteria

- [x] Memory files follow kebab-case naming
- [x] No duplicates with existing plugins
- [x] Content based on official course materials
- [x] SDK patterns reflect Dec 2025 breaking changes
- [ ] Memory files can be imported via `@` syntax (verify after creation)

## Files to Create

| File | Action |
| ------ | -------- |
| `memory/agent-evolution-path.md` | CREATE |
| `memory/core-four-custom.md` | CREATE |
| `memory/system-prompt-architecture.md` | CREATE |
| `memory/custom-tool-patterns.md` | CREATE |
| `memory/agent-deployment-forms.md` | CREATE |
| `skills/custom-agent-design/SKILL.md` | CREATE |
| `skills/tool-design/SKILL.md` | CREATE |
| `skills/agent-governance/SKILL.md` | CREATE |
| `skills/model-selection/SKILL.md` | CREATE |
| `commands/create-agent.md` | CREATE |
| `commands/create-tool.md` | CREATE |
| `commands/list-agent-tools.md` | CREATE |
| `agents/agent-builder.md` | CREATE |
| `agents/tool-scaffolder.md` | CREATE |
| `agents/hook-designer.md` | CREATE |
| `implementation-plan/MASTER-TRACKER.md` | UPDATE |

## SDK Breaking Changes (Dec 2025)

**Critical transformations required**:

| Change | Old (Course) | Current |
| -------- | -------------- | --------- |
| Options class | `ClaudeCodeOptions` | `ClaudeAgentOptions` |
| TypeScript package | `@anthropic-ai/claude-code` | `@anthropic-ai/claude-agent-sdk` |
| Python package | `claude-code-sdk` | `claude-agent-sdk` |
| System prompt | Auto-loaded | Must explicitly set |
| CLAUDE.md | Auto-loaded | Must set `setting_sources=["project"]` |

## Post-Implementation

After creating all components:

1. Verify files load correctly
2. Test `@` import syntax works
3. Update MASTER-TRACKER.md with completed status
4. Proceed to Lesson 012 planning

## Execution Notes

- Focus on SDK patterns that translate to Claude Code subagents
- Note: Orchestrator patterns (spawning subagents from subagents) are SDK-only
- Memory files document patterns; skills provide workflows
- Commands scaffold code for SDK development
