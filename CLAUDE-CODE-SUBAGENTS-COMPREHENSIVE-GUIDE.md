# Claude Code Subagents: Comprehensive Documentation

> **Synthesized from Official Documentation**
> This document consolidates ALL official Claude Code and Claude Agent SDK documentation on subagents/agents.
> Sources: code.claude.com, platform.claude.com, anthropic.com engineering articles

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core Concepts](#2-core-concepts)
3. [Agent File Format](#3-agent-file-format)
4. [Built-in Subagents](#4-built-in-subagents)
5. [Tool Access Configuration](#5-tool-access-configuration)
6. [Model Selection](#6-model-selection)
7. [Priority Resolution](#7-priority-resolution)
8. [Agent Lifecycle](#8-agent-lifecycle)
9. [Session Management](#9-session-management)
10. [Claude Agent SDK](#10-claude-agent-sdk)
11. [Custom Tools & MCP Integration](#11-custom-tools--mcp-integration)
12. [Permissions](#12-permissions)
13. [System Prompts](#13-system-prompts)
14. [Cost Tracking](#14-cost-tracking)
15. [Todo Tracking](#15-todo-tracking)
16. [Structured Outputs](#16-structured-outputs)
17. [Hosting Patterns](#17-hosting-patterns)
18. [Plugin-Provided Agents](#18-plugin-provided-agents)
19. [Hooks Integration](#19-hooks-integration)
20. [Best Practices](#20-best-practices)
21. [Anti-Patterns](#21-anti-patterns)
22. [Example Configurations](#22-example-configurations)
23. [Reference Tables](#23-reference-tables)

---

## 1. Overview

### What are Subagents?

Subagents are pre-configured AI personalities that Claude Code can delegate tasks to. Each subagent:

- Has a **specific purpose and expertise area**
- Uses its **own context window** separate from the main conversation
- Can be configured with **specific tools** it's allowed to use
- Includes a **custom system prompt** that guides its behavior

### Key Benefits

| Benefit | Description |
| :------ | :---------- |
| **Context Preservation** | Each subagent operates in its own context, preventing pollution of the main conversation |
| **Specialized Expertise** | Subagents can be fine-tuned with detailed instructions for specific domains |
| **Reusability** | Once created, subagents can be used across different projects and shared with teams |
| **Flexible Permissions** | Each subagent can have different tool access levels |
| **Parallelization** | Multiple subagents can run concurrently for dramatic speedup |

### Why Use Subagents?

From Anthropic's engineering documentation:

> "Subagents are useful for two main reasons. First, they enable parallelization: you can spin up multiple subagents to work on different tasks simultaneously. Second, they help manage context: subagents use their own isolated context windows, and only send relevant information back to the orchestrator, rather than their full context."

---

## 2. Core Concepts

### Definition Methods

Subagents can be defined in three ways:

1. **Filesystem-based** - Markdown files with YAML frontmatter
2. **CLI-based** - JSON via `--agents` flag
3. **Programmatic** - Via Claude Agent SDK

### Storage Locations

| Type | Location | Scope | Priority |
| :--- | :------- | :---- | :------- |
| **Project subagents** | `.claude/agents/` | Available in current project | Highest |
| **CLI subagents** | `--agents` flag | Session-specific | Medium |
| **User subagents** | `~/.claude/agents/` | Available across all projects | Lower |
| **Plugin agents** | Plugin `agents/` directory | Available when plugin enabled | Per-plugin |

### Invocation Methods

1. **Automatic delegation**: Claude Code proactively delegates based on:
   - The task description in user request
   - The `description` field in subagent configurations
   - Current context and available tools

2. **Explicit invocation**: Request specific subagent by name:

   ```text
   > Use the code-reviewer subagent to check my recent changes
   > Have the debugger subagent investigate this error
   ```

---

## 3. Agent File Format

### Basic Structure

```markdown
---
name: your-sub-agent-name
description: Description of when this subagent should be invoked
tools: tool1, tool2, tool3
model: sonnet
permissionMode: default
skills: skill1, skill2
---

Your subagent's system prompt goes here. This can be multiple paragraphs
and should clearly define the subagent's role, capabilities, and approach.
```

### Configuration Fields

| Field | Required | Type | Description |
| :------ | :--------- | :----- | :------------ |
| `name` | Yes | string | Unique identifier using lowercase letters and hyphens |
| `description` | Yes | string | Natural language description of the subagent's purpose |
| `tools` | No | comma-separated | Specific tools list. If omitted, inherits ALL tools |
| `model` | No | enum | `sonnet`, `opus`, `haiku`, or `'inherit'` |
| `permissionMode` | No | enum | `default`, `acceptEdits`, `bypassPermissions`, `plan`, `ignore` |
| `skills` | No | comma-separated | Skills to auto-load when agent runs |

### Naming Conventions

- Use **lowercase letters and hyphens** only
- Examples: `code-reviewer`, `test-runner`, `security-scanner`
- Names must be unique within their scope (project, user, or plugin)

---

## 4. Built-in Subagents

Claude Code includes three built-in subagents:

### General-purpose Subagent

| Property | Value |
| :--------- | :------ |
| **Model** | Sonnet |
| **Tools** | All tools |
| **Mode** | Read and write files, execute commands |
| **Purpose** | Complex multi-step tasks requiring exploration and action |

**When Claude uses it:**

- Task requires both exploration and modification
- Complex reasoning needed to interpret search results
- Multiple strategies may be needed if initial searches fail
- Task has multiple steps that depend on each other

### Plan Subagent

| Property | Value |
| :--------- | :------ |
| **Model** | Sonnet |
| **Tools** | Read, Glob, Grep, Bash (exploration only) |
| **Purpose** | Research during plan mode before presenting a plan |

**When Claude uses it:**

- Only used in **plan mode**
- When Claude needs to understand codebase to create a plan
- Prevents infinite nesting (subagents cannot spawn other subagents)

### Explore Subagent

| Property | Value |
| :--------- | :------ |
| **Model** | Haiku (fast, low-latency) |
| **Tools** | Glob, Grep, Read, Bash (read-only commands only) |
| **Mode** | Strictly read-only |
| **Purpose** | Rapid file discovery and code exploration |

**Thoroughness levels:**

- **Quick** - Basic searches, fastest results
- **Medium** - Moderate exploration, balances speed and thoroughness
- **Very thorough** - Comprehensive analysis across multiple locations

**When Claude uses it:**

- Search or understand codebase without making changes
- More efficient than main agent running multiple search commands
- Content found doesn't bloat the main conversation

---

## 5. Tool Access Configuration

### Available Built-in Tools

| Tool | Description | Permission Required |
| :----- | :------------ | :------------------- |
| `Read` | Reads file contents | No |
| `Edit` | Makes targeted edits | Yes |
| `Write` | Creates/overwrites files | Yes |
| `Bash` | Executes shell commands | Yes |
| `Glob` | Finds files by pattern | No |
| `Grep` | Searches patterns in files | No |
| `Task` | Runs sub-agents | No |
| `Skill` | Executes skills | Yes |
| `WebFetch` | Fetches URL content | Yes |
| `WebSearch` | Performs web searches | Yes |
| `NotebookEdit` | Edits Jupyter notebooks | Yes |
| `TodoWrite` | Manages todo lists | No |

### Tool Configuration Options

#### Option 1: Inherit All Tools (Default)

```yaml
---
name: my-agent
description: Agent with full tool access
# tools field omitted = inherits ALL tools including MCP tools
---
```

#### Option 2: Specify Individual Tools

```yaml
---
name: read-only-agent
description: Agent with limited tool access
tools: Read, Grep, Glob
---
```

### Common Tool Combinations

```yaml
# Read-only agents (analysis, review):
tools: Read, Grep, Glob

# Test execution agents:
tools: Bash, Read, Grep

# Code modification agents:
tools: Read, Edit, Write, Grep, Glob

# Full development agents:
tools: Read, Edit, Write, Bash, Grep, Glob, Task
```

### Important Notes

- **MCP tools are inherited** when `tools` field is omitted
- Use `/agents` command for interactive interface that lists all available tools
- Tool restrictions apply to the subagent's entire execution

---

## 6. Model Selection

### Available Models

| Model | Alias | Characteristics |
| :------ | :------ | :---------------- |
| **Sonnet** | `sonnet` | Capable reasoning, default for most subagents |
| **Opus** | `opus` | Most powerful, critical decisions |
| **Haiku** | `haiku` | Fast, low-latency, read-only tasks |
| **Inherit** | `'inherit'` | Same model as main conversation |

### Configuration

```yaml
---
name: fast-explorer
description: Quick codebase exploration
model: haiku
---
```

```yaml
---
name: critical-reviewer
description: High-stakes code review
model: opus
---
```

### Environment Variable

Set default subagent model via environment:

```bash
CLAUDE_CODE_SUBAGENT_MODEL=sonnet
```

### Model Selection Guidelines

| Use Case | Recommended Model |
| :--------- | :----------------- |
| Code exploration, file search | Haiku |
| General development tasks | Sonnet |
| Security review, critical decisions | Opus |
| Consistency with main conversation | inherit |

---

## 7. Priority Resolution

When subagent names conflict, priority order is:

1. **Project subagents** (`.claude/agents/`) - Highest
2. **CLI subagents** (`--agents` flag) - Medium
3. **User subagents** (`~/.claude/agents/`) - Lower
4. **Plugin agents** - Per-plugin configuration

**In SDK:** Programmatic agents override filesystem-based agents with same name.

---

## 8. Agent Lifecycle

### Execution Flow

```text
1. Claude encounters task matching subagent expertise
         ↓
2. Subagent is invoked with its own context window
         ↓
3. Subagent works independently using allowed tools
         ↓
4. Subagent returns results to main conversation
         ↓
5. Main conversation continues with clean context
```

### Context Management

- Each subagent has **isolated context window**
- Only **relevant information** sent back to orchestrator
- Main conversation context remains **clean and focused**
- Prevents **context pollution** from detailed exploration

### Limitations

- **Subagents cannot spawn other subagents** (prevents infinite nesting)
- **Recording is disabled during resume** (avoids duplicating messages)
- Subagent cannot access main conversation's full context

---

## 9. Session Management

### Session Resumption

Each subagent execution is assigned a unique `agentId`. Sessions can be resumed:

**Getting Session ID:**

```typescript
for await (const message of response) {
  if (message.type === 'system' && message.subtype === 'init') {
    sessionId = message.session_id;
  }
}
```

**Resuming a Session:**

```typescript
const resumedResponse = query({
  prompt: "Continue where we left off",
  options: {
    resume: sessionId
  }
});
```

### Session Forking

Fork sessions to explore alternatives without modifying original:

```typescript
const forkedResponse = query({
  prompt: "Try a different approach",
  options: {
    resume: sessionId,
    forkSession: true  // Creates new session ID
  }
});
```

| Behavior | `forkSession: false` | `forkSession: true` |
| :--------- | :-------------------- | :------------------- |
| Session ID | Same as original | New generated |
| Original Session | Modified | Preserved |
| Use Case | Continue linear | Branch to explore |

### Use Cases for Resumption

- **Long-running research**: Break down large analysis into multiple sessions
- **Iterative refinement**: Continue refining work without losing context
- **Multi-step workflows**: Sequential tasks while maintaining context

---

## 10. Claude Agent SDK

### Overview

The Claude Agent SDK (formerly Claude Code SDK) is Anthropic's official SDK for building custom AI agents.

### Installation

```bash
# TypeScript
npm install @anthropic-ai/claude-agent-sdk

# Python
pip install claude-agent-sdk
```

### Authentication

```bash
# Anthropic API
export ANTHROPIC_API_KEY=your_key

# Amazon Bedrock
export CLAUDE_CODE_USE_BEDROCK=1

# Google Vertex AI
export CLAUDE_CODE_USE_VERTEX=1

# Microsoft Foundry
export CLAUDE_CODE_USE_FOUNDRY=1
```

### TypeScript Usage

```typescript
import { query } from '@anthropic-ai/claude-agent-sdk';

const result = query({
  prompt: "Review the authentication module",
  options: {
    agents: {
      'code-reviewer': {
        description: 'Expert code review specialist. Use for quality reviews.',
        prompt: `You are a code review specialist...`,
        tools: ['Read', 'Grep', 'Glob'],
        model: 'sonnet'
      }
    }
  }
});

for await (const message of result) {
  console.log(message);
}
```

### Python Usage

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AgentDefinition

options = ClaudeAgentOptions(
    agents={
        'code-reviewer': AgentDefinition(
            description='Expert code review specialist',
            prompt='You are a code review specialist...',
            tools=['Read', 'Grep', 'Glob'],
            model='sonnet'
        )
    }
)

async for message in query(prompt="Review auth module", options=options):
    print(message)
```

### AgentDefinition Type

**TypeScript:**

```typescript
type AgentDefinition = {
  description: string;       // Required - when to use this agent
  prompt: string;            // Required - system prompt
  tools?: string[];          // Optional - inherits all if omitted
  model?: 'sonnet' | 'opus' | 'haiku' | 'inherit';
}
```

**Python:**

```python
@dataclass
class AgentDefinition:
    description: str
    prompt: str
    tools: list[str] | None = None
    model: Literal["sonnet", "opus", "haiku", "inherit"] | None = None
```

### SDK Options Reference

| Option | Type | Description |
| :------- | :----- | :------------ |
| `allowedTools` | `string[]` | List of allowed tool names |
| `disallowedTools` | `string[]` | List of disallowed tool names |
| `permissionMode` | enum | `'default'`, `'acceptEdits'`, `'bypassPermissions'`, `'plan'` |
| `canUseTool` | function | Custom permission callback |
| `mcpServers` | object | MCP server configurations |
| `systemPrompt` | string/object | System prompt configuration |
| `resume` | string | Session ID to resume |
| `forkSession` | boolean | Fork instead of continue session |
| `agents` | object | Programmatic subagent definitions |
| `settingSources` | array | `['user', 'project', 'local']` |
| `plugins` | array | Load custom plugins |
| `sandbox` | object | Sandbox configuration |
| `outputFormat` | JSON Schema | Structured output format |
| `maxTurns` | number | Maximum conversation turns |
| `maxBudgetUsd` | number | Maximum budget in USD |

### Python SDK: query() vs ClaudeSDKClient

| Feature | `query()` | `ClaudeSDKClient` |
| :-------- | :---------- | :------------------ |
| Session | New each time | Reuses same session |
| Conversation | Single exchange | Multiple exchanges |
| Interrupts | Not supported | Supported |
| Hooks | Not supported | Supported |
| Custom Tools | Not supported | Supported |

**ClaudeSDKClient Example:**

```python
from claude_agent_sdk import ClaudeSDKClient

async with ClaudeSDKClient() as client:
    await client.query("What's the capital of France?")
    async for message in client.receive_response():
        print(message)

    # Follow-up - Claude remembers context
    await client.query("What's the population of that city?")
    async for message in client.receive_response():
        print(message)
```

---

## 11. Custom Tools & MCP Integration

### Creating Custom Tools (TypeScript)

```typescript
import { tool, createSdkMcpServer } from "@anthropic-ai/claude-agent-sdk";
import { z } from "zod";

const customServer = createSdkMcpServer({
  name: "my-tools",
  version: "1.0.0",
  tools: [
    tool(
      "get_weather",
      "Get weather for location",
      { latitude: z.number(), longitude: z.number() },
      async (args) => ({
        content: [{ type: "text", text: `Temperature: 72F` }]
      })
    )
  ]
});
```

### Creating Custom Tools (Python)

```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("greet", "Greet a user", {"name": str})
async def greet(args):
    return {
        "content": [{
            "type": "text",
            "text": f"Hello, {args['name']}!"
        }]
    }

calculator = create_sdk_mcp_server(
    name="calculator",
    version="1.0.0",
    tools=[greet]
)
```

### MCP Server Configuration

```typescript
const options = {
  mcpServers: {
    "my-tools": customServer,
    "filesystem": {
      command: "npx",
      args: ["@modelcontextprotocol/server-filesystem"]
    }
  },
  allowedTools: [
    "mcp__my-tools__get_weather",
    "mcp__filesystem__list_files"
  ]
};
```

### Tool Name Format

MCP tools follow the pattern: `mcp__{server_name}__{tool_name}`

### MCP Transport Types

- **stdio** - External processes via stdin/stdout
- **HTTP/SSE** - Remote servers with network communication
- **SDK** - In-process servers within your application

**Important:** Custom MCP tools require **streaming input mode** (async generator).

---

## 12. Permissions

### Permission Modes

| Mode | Description |
| :----- | :------------ |
| `default` | Standard permission behavior |
| `acceptEdits` | Auto-accept file edits |
| `bypassPermissions` | Bypass all permission checks |
| `plan` | Planning mode - no execution |
| `ignore` | Ignore permission mode |

### Permission Flow

```text
PreToolUse Hook
      ↓
  Deny Rules
      ↓
 Allow Rules
      ↓
  Ask Rules
      ↓
Permission Mode
      ↓
canUseTool Callback
      ↓
PostToolUse Hook
```

### Custom Permission Handler (SDK)

```typescript
canUseTool: async (toolName, input) => {
  if (toolName === "Write" && input.file_path.startsWith("/system/")) {
    return {
      behavior: "deny",
      message: "System directory write not allowed",
      interrupt: true
    };
  }
  return {
    behavior: "allow",
    updatedInput: input
  };
}
```

---

## 13. System Prompts

### Four Approaches

1. **CLAUDE.md files** - Project-level (requires `settingSources: ['project']`)
2. **Output styles** - Persistent file-based configurations
3. **`systemPrompt` with append** - Extends Claude Code's prompt
4. **Custom `systemPrompt`** - Complete replacement

### Using Preset with Append

```typescript
systemPrompt: {
  type: "preset",
  preset: "claude_code",
  append: "Always include detailed docstrings and type hints."
}
```

### Loading CLAUDE.md

```typescript
options: {
  systemPrompt: { type: "preset", preset: "claude_code" },
  settingSources: ["project"]  // REQUIRED to load CLAUDE.md
}
```

**Important:** Default system prompt is **empty** - use preset `claude_code` to get Claude Code's system prompt.

---

## 14. Cost Tracking

### Key Concepts

- **Steps**: A single request/response pair
- **Messages**: Individual messages within a step
- **Usage**: Token consumption data

### Cost Tracking Fields

| Field | Description |
| :------ | :------------ |
| `input_tokens` | Base input tokens processed |
| `output_tokens` | Tokens generated in response |
| `cache_creation_input_tokens` | Tokens used to create cache entries |
| `cache_read_input_tokens` | Tokens read from cache |
| `service_tier` | Service tier used |
| `total_cost_usd` | Total cost in USD (only in result message) |

### Critical Rules

1. **Same ID = Same Usage**: All messages with same `id` report identical usage
2. **Charge Once Per Step**: Only charge once per step, not per message
3. **Result Message Contains Cumulative Usage**: Final `result` message has total

### Average Costs

- **$6** per developer per day average
- **$12** per day for 90% of users
- **~$100-200**/developer per month with Sonnet 4.5

---

## 15. Todo Tracking

### Todo States

| State | Description |
| :------ | :------------ |
| `pending` | Task not yet started |
| `in_progress` | Currently working on |
| `completed` | Task finished successfully |

### When Todos Are Used

- Complex multi-step tasks (3+ distinct actions)
- User-provided task lists with multiple items
- Non-trivial operations benefiting from progress tracking
- Explicit user requests

### Implementation Example

```typescript
for await (const message of query({
  prompt: "Optimize my React app and track progress",
  options: { maxTurns: 15 }
})) {
  if (message.type === "assistant") {
    for (const block of message.message.content) {
      if (block.type === "tool_use" && block.name === "TodoWrite") {
        const todos = block.input.todos;
        todos.forEach((todo, index) => {
          console.log(`${index + 1}. [${todo.status}] ${todo.content}`);
        });
      }
    }
  }
}
```

---

## 16. Structured Outputs

### When to Use

- When you need validated JSON after agent completes work
- For file searches, command execution, web research needing structured results
- For type-safe integration with your application

### Implementation with Zod

```typescript
import { z } from 'zod'
import { zodToJsonSchema } from 'zod-to-json-schema'

const AnalysisResult = z.object({
  summary: z.string(),
  issues: z.array(z.object({
    severity: z.enum(['low', 'medium', 'high']),
    description: z.string(),
    file: z.string()
  })),
  score: z.number().min(0).max(100)
})

const schema = zodToJsonSchema(AnalysisResult, { $refStrategy: 'root' })

for await (const message of query({
  prompt: 'Analyze the codebase for security issues',
  options: {
    outputFormat: {
      type: 'json_schema',
      schema: schema
    }
  }
})) {
  if (message.type === 'result' && message.structured_output) {
    const parsed = AnalysisResult.safeParse(message.structured_output)
    // Type-safe access to data
  }
}
```

---

## 17. Hosting Patterns

### Pattern 1: Ephemeral Sessions

- Create new container per task, destroy when complete
- Best for: Bug investigation, invoice processing, translation

### Pattern 2: Long-Running Sessions

- Maintain persistent container instances
- Multiple Claude Agent processes inside container
- Best for: Email agents, site builders, high-frequency chat bots

### Pattern 3: Hybrid Sessions

- Ephemeral containers hydrated with history from database/SDK resumption
- Best for: Personal project managers, deep research, customer support

### Pattern 4: Single Containers

- Multiple Claude Agent SDK processes in one global container
- Best for: Agent simulations where agents must collaborate

### Hosting Requirements

| Requirement | Value |
| :------------ | :------ |
| Python | 3.10+ |
| Node.js | 18+ |
| RAM | 1GiB recommended |
| Disk | 5GiB recommended |
| CPU | 1 core |
| Network | Outbound HTTPS to `api.anthropic.com` |

### Sandbox Providers

- Cloudflare Sandboxes
- Modal Sandboxes
- Daytona
- E2B
- Fly Machines
- Vercel Sandbox

---

## 18. Plugin-Provided Agents

### Structure

```text
my-plugin/
  .claude-plugin/
    plugin.json          # Required: plugin manifest
  commands/              # Custom slash commands
  agents/                # Custom agents
  skills/                # Agent Skills
  hooks/                 # Event handlers
  .mcp.json             # MCP server definitions
```

### Loading Plugins in SDK

```typescript
for await (const message of query({
  prompt: "Hello",
  options: {
    plugins: [
      { type: "local", path: "./my-plugin" },
      { type: "local", path: "/absolute/path/to/plugin" }
    ]
  }
})) {
  // Plugin agents are now available
}
```

### Key Points

- Plugin agents work identically to user-defined agents
- Appear in `/agents` interface alongside custom agents
- Can be invoked explicitly or automatically

---

## 19. Hooks Integration

### SubagentStop Hook

Runs when a Claude Code subagent (Task tool call) has finished responding.

**Input Schema:**

```json
{
  "session_id": "abc123",
  "transcript_path": "~/.claude/projects/.../00893aaf-...jsonl",
  "permission_mode": "default",
  "hook_event_name": "SubagentStop",
  "stop_hook_active": true
}
```

**Decision Control:**

```json
{
  "decision": "block",
  "reason": "Must be provided when Claude is blocked from stopping"
}
```

**Prompt-based Hook Example:**

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Evaluate if this subagent should stop. Check if task completed."
          }
        ]
      }
    ]
  }
}
```

---

## 20. Best Practices

### Agent Design

1. **Start with Claude-generated agents**: Generate initial subagent with Claude, then iterate
2. **Design focused subagents**: Single, clear responsibilities
3. **Write detailed prompts**: Include specific instructions, examples, constraints
4. **Limit tool access**: Only grant necessary tools
5. **Version control**: Check project subagents into version control

### Encouraging Proactive Use

Include phrases in `description` field:

- "use PROACTIVELY"
- "MUST BE USED"
- "Use immediately after..."

### Parallelization

- Run multiple subagents concurrently for complex workflows
- Example: `style-checker`, `security-scanner`, `test-coverage` simultaneously

### Model Selection

| Use Case | Model |
| :--------- | :------ |
| Fast, read-only searches | Haiku |
| General development | Sonnet |
| Critical decisions | Opus |
| Consistency | inherit |

### Cost Management

1. Use Message IDs for deduplication
2. Monitor Result Message for authoritative usage
3. Implement logging for auditing
4. Handle failures gracefully
5. Track partial usage on errors

### Session Management

1. Always capture session ID for resumption
2. Use forking when exploring alternatives
3. Implement session cleanup for ephemeral patterns
4. Set `maxTurns` to prevent loops

---

## 21. Anti-Patterns

| Anti-Pattern | Problem | Solution |
| :------------- | :-------- | :--------- |
| One agent does everything | Reduced performance, predictability | Create focused agents |
| Not limiting tool access | Reduced security, focus | Specify minimal tools |
| Vague prompts | Unnecessary scanning, token waste | Write detailed prompts |
| Double-charging | Billing errors | Deduplicate by message ID |
| Not setting maxTurns | Agents stuck in loops | Set reasonable limit |
| Not using fork for experiments | Modifies original session | Use `forkSession: true` |
| Ignoring background costs | Budget overruns | Track summarization (~$0.04/session) |

---

## 22. Example Configurations

### Code Reviewer

```markdown
---
name: code-reviewer
description: Expert code review specialist. Proactively reviews code for quality, security, and maintainability. Use immediately after writing or modifying code.
tools: Read, Grep, Glob, Bash
model: inherit
---

You are a senior code reviewer ensuring high standards of code quality and security.

When invoked:
1. Run git diff to see recent changes
2. Focus on modified files
3. Begin review immediately

Review checklist:
- Code is simple and readable
- Functions and variables are well-named
- No duplicated code
- Proper error handling
- No exposed secrets or API keys
- Input validation implemented
- Good test coverage
- Performance considerations addressed
```

### Debugger

```markdown
---
name: debugger
description: Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issues.
tools: Read, Edit, Bash, Grep, Glob
---

You are an expert debugger specializing in root cause analysis.

When invoked:
1. Capture error message and stack trace
2. Identify reproduction steps
3. Isolate the failure location
4. Implement minimal fix
5. Verify solution works
```

### Security Scanner

```markdown
---
name: security-scanner
description: Security specialist. Use PROACTIVELY before any code is committed. MUST BE USED for authentication, authorization, or data handling code.
tools: Read, Grep, Glob
model: opus
---

You are a security specialist focused on identifying vulnerabilities.

Scan for:
- SQL injection
- XSS vulnerabilities
- Authentication bypasses
- Authorization flaws
- Sensitive data exposure
- Insecure configurations
```

### Test Runner

```markdown
---
name: test-runner
description: Test execution and fixing specialist. Use when tests need to be run or when test failures occur.
tools: Bash, Read, Edit, Grep, Glob
---

You are a testing specialist.

When invoked:
1. Run relevant test suite
2. Analyze any failures
3. Implement fixes for failing tests
4. Re-run to verify
5. Report results
```

### CLI Configuration

```bash
claude --agents '{
  "code-reviewer": {
    "description": "Expert code reviewer. Use proactively after code changes.",
    "prompt": "You are a senior code reviewer...",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  },
  "debugger": {
    "description": "Debugging specialist for errors and test failures.",
    "prompt": "You are an expert debugger..."
  }
}'
```

---

## 23. Reference Tables

### All YAML Frontmatter Fields

| Field | Required | Values | Default |
| :------ | :--------- | :------- | :-------- |
| `name` | Yes | lowercase-with-hyphens | - |
| `description` | Yes | natural language | - |
| `tools` | No | comma-separated list | inherit all |
| `model` | No | `sonnet`, `opus`, `haiku`, `'inherit'` | `sonnet` |
| `permissionMode` | No | `default`, `acceptEdits`, `bypassPermissions`, `plan`, `ignore` | `default` |
| `skills` | No | comma-separated list | none |

### SDK AgentDefinition Fields

| Field | TypeScript Type | Python Type | Required |
| :------ | :---------------- | :------------ | :--------- |
| `description` | `string` | `str` | Yes |
| `prompt` | `string` | `str` | Yes |
| `tools` | `string[]` | `list[str]` | No |
| `model` | `'sonnet' \| 'opus' \| 'haiku' \| 'inherit'` | `Literal[...]` | No |

### Built-in Subagent Comparison

| Subagent | Model | Tools | Can Modify Files | Use Case |
| :--------- | :------ | :------ | :----------------- | :--------- |
| General-purpose | Sonnet | All | Yes | Complex multi-step tasks |
| Plan | Sonnet | Read, Glob, Grep, Bash | No | Codebase research in plan mode |
| Explore | Haiku | Glob, Grep, Read, Bash (read-only) | No | Fast file discovery |

### Documentation Sources

| Source | URL | Description |
| :------- | :---- | :------------ |
| Claude Code Subagents | <https://code.claude.com/docs/en/sub-agents> | Primary subagent documentation |
| Agent SDK Overview | <https://platform.claude.com/docs/en/agent-sdk/overview> | SDK installation and setup |
| Agent SDK TypeScript | <https://platform.claude.com/docs/en/agent-sdk/typescript> | TypeScript API reference |
| Agent SDK Python | <https://platform.claude.com/docs/en/agent-sdk/python> | Python API reference |
| Agent SDK Subagents | <https://platform.claude.com/docs/en/agent-sdk/subagents> | SDK subagent integration |
| Agent SDK Sessions | <https://platform.claude.com/docs/en/agent-sdk/sessions> | Session management |
| Agent SDK Permissions | <https://platform.claude.com/docs/en/agent-sdk/permissions> | Permission system |
| Agent SDK Custom Tools | <https://platform.claude.com/docs/en/agent-sdk/custom-tools> | Custom tool creation |
| Agent SDK MCP | <https://platform.claude.com/docs/en/agent-sdk/mcp> | MCP integration |
| Agent SDK Cost Tracking | <https://platform.claude.com/docs/en/agent-sdk/cost-tracking> | Cost management |
| Agent SDK Todo Tracking | <https://platform.claude.com/docs/en/agent-sdk/todo-tracking> | Todo system |
| Agent SDK Structured Outputs | <https://platform.claude.com/docs/en/agent-sdk/structured-outputs> | JSON schema outputs |
| Agent SDK Hosting | <https://platform.claude.com/docs/en/agent-sdk/hosting> | Deployment patterns |
| Agent SDK Plugins | <https://platform.claude.com/docs/en/agent-sdk/plugins> | Plugin integration |
| Hooks Reference | <https://code.claude.com/docs/en/hooks> | Hook events including SubagentStop |
| CLI Reference | <https://code.claude.com/docs/en/cli-reference> | --agents flag |
| Skills Reference | <https://code.claude.com/docs/en/skills> | Skills vs agents |
| Settings Reference | <https://code.claude.com/docs/en/settings> | Available tools list |
| Costs | <https://code.claude.com/docs/en/costs> | Cost information |
| Common Workflows | <https://code.claude.com/docs/en/common-workflows> | Usage patterns |
| Building Agents (Anthropic) | anthropic.com/engineering/building-agents-with-the-claude-agent-sdk | Best practices |

---

## Document Metadata

**Created:** 2025-12-04
**Source:** Official Claude Code and Claude Agent SDK documentation
**Purpose:** Comprehensive reference for implementing and using Claude Code subagents

---

*This document was synthesized from exhaustive research across all official documentation sources.*
