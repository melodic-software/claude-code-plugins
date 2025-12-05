# Lesson 11 Analysis: Building Domain-Specific Agents - Claude Code SDK Mastery

> **SDK BREAKING CHANGES (Dec 2025)**
> The Claude Agent SDK has breaking changes since course recording:
>
> | Change | Old (Course) | Current |
> | --- | --- | --- |
> | Options class | `ClaudeCodeOptions` | `ClaudeAgentOptions` |
> | TypeScript package | `@anthropic-ai/claude-code` | `@anthropic-ai/claude-agent-sdk` |
> | Python package | `claude-code-sdk` | `claude-agent-sdk` |
> | System prompt | Auto-loaded | Must explicitly set |
> | CLAUDE.md | Auto-loaded | Must set `setting_sources=["project"]` |
>
> See: `code.claude.com/docs/en/sdk/migration-guide`

## Content Summary

### Core Tactic

**Build Custom Agents** - Move from generic agents to domain-specific powerhouses with full SDK control. Custom agents let you take the Core Four (Context, Model, Prompt, Tools) and scale them beyond the defaults to solve domain-specific problems with targeted, repeatable workflows.

### Key Frameworks

#### The Agent Evolution Path

| Level | Name | Description |
| ----- | ---- | ----------- |
| 1 | Base Agents | Out-of-the-box agents (Claude Code, Codex CLI, Gemini CLI) |
| 2 | Better Agents | Prompt engineering + context engineering |
| 3 | More Agents | Scaling compute with multiple agents |
| 4 | Custom Agents | Domain-specific solutions with full SDK control |

#### The Mismatch Problem

> "Out-of-the-box agents are built for everyone's codebase, not yours. This mismatch can cost you hundreds of hours and millions of tokens."

Custom agents solve this by:

- Passing domain-specific knowledge directly to agents
- Creating targeted, repeatable workflows
- Protecting codebases from wrong tool calls
- Pushing one agent, one prompt, one purpose to limits

#### The Core Four at Scale

| Element | Out-of-Box | Custom Agent |
| ------- | ---------- | ------------ |
| **Context** | Generic CLAUDE.md | Domain-specific system prompt |
| **Model** | Default (Sonnet) | Task-appropriate (Haiku/Sonnet/Opus) |
| **Prompt** | User prompts only | Full system prompt control |
| **Tools** | 15+ default tools | Precise tool set (disallow unused) |

### Agent Patterns from Lesson

#### 1. Pong Agent (System Prompt Control)

```python
# Simplest custom agent - complete system prompt override
options = ClaudeCodeOptions(
    model="claude-4-sonnet",
    system_prompt=load_system_prompt("prompts/pong_system.md")
)
```markdown

**Key Insight**: When you override the system prompt, this is NOT Claude Code anymore. You've created a new product entirely.

#### 2. Echo Agent (Custom Tools)

```python
@tool(
    name="echo_text",
    description="Echoes text with optional transformations"
)
def echo_tool(args: dict) -> dict:
    # Deterministic code - do whatever you want
    text = args.get("text", "")
    return {"result": transform(text)}

# Create in-memory MCP server
options = ClaudeCodeOptions(
    model="claude-haiku",
    system_prompt=load_system_prompt(),
    mcp_servers=[create_sdk_mcp_server(tools=[echo_tool])]
)
```markdown

**Key Insight**: Tools are built with `@tool` decorator. The description tells your agent how to use the tool.

#### 3. Calculator Agent (Focused Functionality)

```python
options = ClaudeCodeOptions(
    model="claude-4-sonnet",
    system_prompt=load_system_prompt(),
    disallowed_tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep", ...],
    mcp_servers=[create_sdk_mcp_server(tools=[calculate, convert])]
)
```markdown

**Key Insight**: Disallow tools your agent doesn't need - they consume context window space.

#### 4. Social Hype Agent (Data Streaming)

- Processes real-time data streams (WebSocket firehose)
- Sentiment analysis on incoming content
- Notification system for important matches
- Workflow embedded in system prompt (always same behavior)

#### 5. QA Agent (Codebase Expert with Hooks)

```python
options = ClaudeCodeOptions(
    system_prompt=load_system_prompt(),
    model="claude-4-sonnet",
    mcp_config_path="mcp_config.json",  # Connect to MCP servers
    allowed_tools=["Task", "Bash", "Glob", "Grep", "Read"],
    hooks={
        "pre_tool_use": [
            {
                "matcher": {"tool_name": "Read"},
                "command": "python block_env_files.py"
            }
        ]
    }
)
```markdown

**Key Insight**: Hooks enable governance and permission checks in custom agents.

#### 6. Try Copywriter (UI-Embedded Multi-Variation)

```python
options = ClaudeCodeOptions(
    system_prompt=load_system_prompt(),  # Has NUM_VERSIONS variable
    model="claude-4-sonnet",
    disallowed_tools=["*"]  # No tools - pure text generation
)
```markdown

**Key Insight**: Custom agents can be embedded in UIs as backend API methods.

#### 7. Micro SDLC Agent (Plan-Build-Review Workflow)

```python
# Planner Agent - write hook limits to specs directory only
planner_options = ClaudeCodeOptions(
    system_prompt=load_system_prompt("prompts/planner_system.md"),
    hooks={"pre_tool_use": [planner_write_hook]}
)

# Builder Agent - uses default Claude Code tools
builder_options = ClaudeCodeOptions(
    model="claude-4-sonnet",
    permission_mode="auto"  # Let builder do what it needs
)

# Reviewer Agent - appends to system prompt (extends Claude Code)
reviewer_options = ClaudeCodeOptions(
    append_system_prompt=load_system_prompt("prompts/reviewer_append.md")
)
```markdown

**Key Insight**: Don't always override - append system prompt to extend Claude Code.

#### 8. UltraStream Agent (Log Processing with Inspector)

- Two agents: Stream Agent (processes logs) + Inspector Agent (queries results)
- Custom tools for token-efficient log reading
- Fine-grained tools solve context window problems

### Implementation Patterns

#### Query vs Client Pattern

```python
# Query() - One-off prompts
from claude_code import query
response = query(prompt, options=options)

# Claude SDK Client - Multi-turn conversations
from claude_code import ClaudeSdkClient
client = ClaudeSdkClient(options)
response1 = client.query(prompt1)
response2 = client.query(prompt2)  # Maintains conversation
```markdown

#### Session Management

```python
# Get session ID from result message
session_id = result_message.session_id

# Resume conversation
options = ClaudeCodeOptions(
    ...,
    resume=session_id  # Continue from previous context
)
```markdown

#### Response Block Handling

```python
for message in response:
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                print(block.text)
            elif isinstance(block, ToolUseBlock):
                print(f"Tool: {block.name}")
            elif isinstance(block, ToolResultBlock):
                print(f"Result: {block.content}")
    elif isinstance(message, ResultMessage):
        print(f"Cost: {message.total_cost}")
        print(f"Session: {message.session_id}")
```yaml

### Anti-Patterns Identified

- **Competing with Claude Code**: Don't try to build a better engineering agent
- **System prompt for generic work**: Use out-of-box agents when work is generic
- **Tool overload**: Keeping 15+ default tools when you need 2
- **Missing governance**: No hooks for permission/access control
- **Ignoring context overhead**: Tools consume space even if unused
- **Overriding when extending works**: Use append_system_prompt when possible

### When to Build Custom Agents

**Build custom agents when:**

- You need programmatic agents
- Solving repeat workflows with agents
- Domain-specific problems that out-of-box can't solve
- Keeping costs down while maintaining performance
- You need permission checks and governance
- You want to stay out of the loop

**Use out-of-box agents when:**

- Operating in the loop (prompting back and forth)
- Workflow is generic enough
- Exploring or prototyping
- Tasks are short-lived and lightweight
- You need a balanced generalist agent

### Metrics/KPIs

Custom agent success indicators:

- **Token efficiency**: Tokens used vs work accomplished
- **Tool precision**: Only needed tools available
- **Context focus**: Minimal context window usage
- **Repeatability**: Consistent results per domain

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `custom-agent-design` | Design custom agents from scratch | custom agent, SDK, system prompt, tools |
| `tool-design` | Create custom tools with @tool decorator | tool, decorator, MCP, in-memory |
| `agent-governance` | Implement hooks for permission control | hooks, governance, permission, block |
| `model-selection` | Choose appropriate model for task | haiku, sonnet, opus, model, cost |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `agent-builder` | Build custom agent configurations | Read, Write, Bash |
| `tool-scaffolder` | Generate custom tool boilerplate | Read, Write |
| `hook-designer` | Design permission hooks | Read, Write, Glob |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/create_agent` | Scaffold a new custom agent | `$1` agent_name, `$2` purpose |
| `/create_tool` | Generate custom tool with decorator | `$1` tool_name, `$2` description |
| `/list_agent_tools` | List available tools for agent | None |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `agent-evolution-path.md` | Base -> Better -> More -> Custom | When planning agent strategy |
| `core-four-custom.md` | Controlling Core Four in custom agents | When building custom agents |
| `system-prompt-architecture.md` | Override vs append patterns | When configuring system prompts |
| `custom-tool-patterns.md` | @tool decorator and MCP patterns | When creating tools |
| `agent-deployment-forms.md` | Scripts, UIs, streams, terminals | When deploying agents |

## Key Insights for Plugin Development

### High-Value Components from Lesson 11

1. **Memory File: `core-four-custom.md`**
   - How to control Context, Model, Prompt, Tools
   - Default vs custom configurations
   - Token overhead considerations

2. **Memory File: `system-prompt-architecture.md`**
   - Override: Complete custom agent
   - Append: Extend Claude Code
   - When to use each approach

3. **Skill: `custom-agent-design`**
   - Agent pattern selection
   - SDK configuration
   - Deployment considerations

4. **Agent Templates**
   - Pong (minimal)
   - Echo (custom tools)
   - Calculator (focused)
   - QA (hooks/governance)
   - SDLC (multi-agent workflow)

### Key Quotes

> "The system prompt is the most important element of your custom agents, with zero exceptions."
>
> "When you override the system prompt, this is NOT Claude Code anymore. You've created a new product entirely."
>
> "15 extra tools consume space in your agent's mind. Use /context to understand what's going into your agent."
>
> "Custom agents let you template your engineering directly into your agent and push one agent, one prompt, one purpose to its limits."
>
> "All the alpha in engineering is in the hard specific problems that most engineers and most agents can't solve out of the box."
>
> "It's not about what you can do anymore. It's about what you can teach your agents to do."

### Claude Code SDK Architecture

```text
ClaudeCodeOptions Configuration:
├── model: "haiku" | "sonnet" | "opus"
├── system_prompt: str | None (override)
├── append_system_prompt: str | None (extend)
├── allowed_tools: list[str]
├── disallowed_tools: list[str]
├── mcp_servers: list[MCPServer]
├── mcp_config_path: str
├── hooks: dict
├── resume: str (session_id)
├── permission_mode: str
└── max_turns: int

Response Types:
├── AssistantMessage
│   ├── TextBlock
│   ├── ToolUseBlock
│   ├── ToolResultBlock
│   └── ThinkingBlock
└── ResultMessage
    ├── session_id
    ├── total_cost
    └── context_window_usage
```markdown

### Agent Deployment Forms

| Form | Use Case | Example |
| ---- | -------- | ------- |
| Script | ADWs, automation | adw_plan.py |
| Terminal UI | Interactive tools | Calculator agent |
| Backend API | UI integration | Try Copywriter |
| Data Stream | Real-time processing | Social Hype |
| Multi-Agent | Complex workflows | Micro SDLC |

## Implementation Patterns from Repo (building-specialized-agents)

### Repository Structure

The companion repository at `D:/repos/gh/disler/building-specialized-agents/` contains 8 progressive agent implementations:

```text
apps/
├── custom_1_pong_agent/         # Basic SDK setup, system prompt override
├── custom_2_echo_agent/         # Custom tools with @tool decorator
├── custom_3_calc_agent/         # REPL with session resumption
├── custom_4_social_hype_agent/  # Real-time data stream processing
├── custom_5_qa_agent/           # Codebase QA with inline hooks
├── custom_6_tri_copy_writer/    # Web UI with structured JSON responses
├── custom_7_micro_sdlc_agent/   # Multi-agent orchestration (Plan/Build/Review)
└── custom_8_ultra_stream_agent/ # Dual-agent log processing system
```markdown

> **Editor's Note (Dec 2025)**: The original examples use `ClaudeCodeOptions`, which has been renamed to `ClaudeAgentOptions` in current SDK versions. Also note that model IDs like `claude-sonnet-4-20250514` may be outdated - verify current model identifiers at [docs.anthropic.com/models](https://docs.anthropic.com/claude/docs/models).

### Pattern 1: Basic Agent with System Prompt Override

**File:** `apps/custom_1_pong_agent/pong_agent.py`

```python
from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    TextBlock,
    ResultMessage,
)

def load_system_prompt() -> str:
    """Load system prompt from markdown file"""
    prompt_file = Path(__file__).parent / "prompts" / "PONG_AGENT_SYSTEM_PROMPT.md"
    with open(prompt_file, "r") as file:
        return file.read().strip()

async def main():
    # Configure agent with complete system prompt override
    options = ClaudeAgentOptions(
        system_prompt=load_system_prompt(),
        model="claude-sonnet-4-20250514",
    )

    # Send query and process responses
    async for message in query(prompt=input_prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)

        elif isinstance(message, ResultMessage):
            print(f"Session ID: {message.session_id}")
            print(f"Cost: ${message.total_cost_usd:.6f}")
```markdown

**System Prompt Example:**

```markdown
# Pong Agent

## Purpose

You are a pong agent. Always respond with exactly 'pong' to ANY input, nothing more, nothing less.
```markdown

**Key Insight:** When you override `system_prompt`, you completely replace Claude Code's default behavior. This is creating a new agent product, not extending Claude Code.

### Pattern 2: Custom Tools with @tool Decorator

**File:** `apps/custom_2_echo_agent/echo_agent.py`

```python
from claude_agent_sdk import (
    tool,
    create_sdk_mcp_server,
    ClaudeSDKClient,
    ClaudeAgentOptions,
    AssistantMessage,
    TextBlock,
    ToolUseBlock,
)

@tool(
    "echo",
    "Echo a message with transformations",
    {"message": str, "repeat": int, "transform": str},
)
async def echo_tool(args: dict[str, Any]) -> dict[str, Any]:
    """Custom tool with parameters"""
    message = args["message"]
    repeat = args.get("repeat", 1)
    transform = args.get("transform", "none")

    # Apply transformation
    if transform == "uppercase":
        message = message.upper()
    elif transform == "lowercase":
        message = message.lower()
    elif transform == "reverse":
        message = message[::-1]

    # Repeat and return
    result = " ".join([message] * repeat)
    return {"content": [{"type": "text", "text": result}]}

async def main():
    # Create MCP server with custom tool
    echo_server = create_sdk_mcp_server(
        name="echo_server",
        version="1.0.0",
        tools=[echo_tool]
    )

    # Configure agent with MCP server and tool access
    options = ClaudeAgentOptions(
        mcp_servers={"echo": echo_server},
        allowed_tools=["mcp__echo__echo"],  # Format: mcp__<server>__<tool>
        system_prompt=load_system_prompt(),
        model="claude-3-5-haiku-20241022",
    )

    # Use ClaudeSDKClient for custom tools (query() doesn't support them!)
    async with ClaudeSDKClient(options=options) as client:
        await client.query(user_prompt)

        async for message in client.receive_response():
            if isinstance(message, AssistantMessage):
                for block in message.content:
                    if isinstance(block, ToolUseBlock):
                        print(f"Tool: {block.name}")
                    elif isinstance(block, TextBlock):
                        print(block.text)
```markdown

**Key Insights:**

- Custom tools are defined with `@tool` decorator
- `create_sdk_mcp_server()` creates in-memory MCP server
- Tool naming: `mcp__<server_name>__<tool_name>`
- Must use `ClaudeSDKClient`, not `query()` for custom tools
- Tools return dict with `content` key containing response blocks

### Pattern 3: Session Resumption for Conversation Continuity

**File:** `apps/custom_3_calc_agent/calc_agent.py`

```python
from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    ResultMessage,
)

async def run_calculator_repl():
    """REPL with session continuity via resume parameter"""

    # Track session ID across queries
    current_session_id = None
    total_session_cost = 0.0

    while True:
        user_input = input("Calculator> ")

        # Create options with resume parameter
        options = ClaudeAgentOptions(
            mcp_servers={"calculator": calculator_mcp_server},
            allowed_tools=[
                "mcp__calculator__custom_math_evaluator",
                "mcp__calculator__custom_unit_converter",
            ],
            disallowed_tools=[
                "Read", "Write", "Edit", "Bash", "Glob", "Grep",
                "WebFetch", "WebSearch", "TodoWrite", "Task",
            ],
            system_prompt=calculator_system_prompt,
            model="claude-sonnet-4-20250514",
            resume=current_session_id,  # KEY: Maintains conversation history!
        )

        async with ClaudeSDKClient(options=options) as client:
            await client.query(user_input)

            async for message in client.receive_response():
                if isinstance(message, ResultMessage):
                    # CRITICAL: Capture session_id for next query
                    if message.session_id:
                        current_session_id = message.session_id

                    # Track costs
                    if message.total_cost_usd:
                        total_session_cost += message.total_cost_usd
```markdown

**Key Insights:**

- `resume=current_session_id` maintains conversation history
- Capture `session_id` from `ResultMessage` after each query
- Reuse captured `session_id` in next query's options
- Allows agent to remember previous conversation context
- Essential for REPL and interactive agents

### Pattern 4: Inline Hooks for Security and Governance

**File:** `apps/custom_5_qa_agent/qa_agent.py`

```python
from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    HookMatcher,
    HookContext,
)

async def block_env_files(
    input_data: dict[str, Any],
    tool_use_id: str | None,
    context: HookContext
) -> dict[str, Any]:
    """Hook to block .env file access"""

    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})
    file_path = tool_input.get("file_path", "")

    # Only check Read operations
    if tool_name != "Read":
        return {}

    # Block .env files
    if ".env" in file_path:
        return {
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": "Security policy: .env files are blocked",
            }
        }

    return {}

async def log_tool_usage(
    input_data: dict[str, Any],
    tool_use_id: str | None,
    context: HookContext
) -> dict[str, Any]:
    """Hook to log all tool usage for auditing"""

    tool_name = input_data.get("tool_name", "")
    print(f"[AUDIT] Tool used: {tool_name}")
    return {}

# Configure agent with inline hooks
hooks = {
    "PreToolUse": [
        HookMatcher(matcher="Read", hooks=[block_env_files]),  # Specific tool
        HookMatcher(hooks=[log_tool_usage]),  # All tools
    ],
    "PostToolUse": [
        HookMatcher(hooks=[log_tool_usage])
    ],
}

options = ClaudeAgentOptions(
    system_prompt=system_prompt,
    allowed_tools=["Task", "Bash", "Glob", "Grep", "Read"],
    model="claude-sonnet-4-20250514",
    resume=resume_session,
    hooks=hooks,  # Inline hooks work for subagents too!
)
```markdown

**Key Insights:**

- Hooks are Python async functions with signature: `(input_data, tool_use_id, context) -> dict`
- `HookMatcher` can target specific tools via `matcher` parameter
- `HookMatcher` without `matcher` applies to all tools
- Return `permissionDecision: "deny"` to block tool execution
- Return empty dict `{}` to allow execution
- Hooks work for both main agent and subagents spawned via Task tool

### Pattern 5: Multi-Agent Orchestration

**File:** `apps/custom_7_micro_sdlc_agent/backend/modules/agent_orchestrator.py`

```python
from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    AssistantMessage,
    TextBlock,
    ToolUseBlock,
    ResultMessage,
    ThinkingBlock,
)

def load_prompt(prompt_path: str, variables: Dict[str, str]) -> str:
    """Load prompt file and replace variables"""
    prompt_file = Path(__file__).parent.parent / prompt_path
    with open(prompt_file, "r") as f:
        content = f.read()

    # Replace variables like {TICKET_TITLE}, {TICKET_DESCRIPTION}
    for key, value in variables.items():
        content = content.replace(f"{{{key}}}", str(value))

    return content

async def run_planner_agent(ticket_data):
    """Planner agent creates implementation plans"""
    system_prompt = load_prompt(
        "prompts/planner_system.md",
        {
            "TICKET_TITLE": ticket_data["title"],
            "TICKET_DESCRIPTION": ticket_data["description"],
        }
    )

    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        model="claude-sonnet-4-20250514",
        # Hook to restrict Write to plans/ directory only
        hooks={"PreToolUse": [planner_write_hook]},
    )

    async with ClaudeSDKClient(options=options) as client:
        await client.query("Create implementation plan")
        async for message in client.receive_response():
            if isinstance(message, ThinkingBlock):
                # Show agent thinking process
                log_thinking(message.thinking)
            elif isinstance(message, ToolUseBlock):
                # Log tool usage
                log_tool_call(message.name, message.input)

async def run_builder_agent(plan_path):
    """Builder agent executes the plan"""
    options = ClaudeAgentOptions(
        system_prompt=load_prompt("prompts/builder_system.md", {}),
        model="claude-sonnet-4-20250514",
        permission_mode="auto",  # Let builder do what it needs
    )

    async with ClaudeSDKClient(options=options) as client:
        await client.query(f"Execute plan at {plan_path}")
        # Process response...

async def run_reviewer_agent(plan_path, implementation_paths):
    """Reviewer agent validates implementation against plan"""

    # Use append_system_prompt to EXTEND Claude Code, not override
    options = ClaudeAgentOptions(
        append_system_prompt=load_prompt("prompts/reviewer_append.md", {}),
        model="claude-sonnet-4-20250514",
    )

    async with ClaudeSDKClient(options=options) as client:
        await client.query(f"Review implementation against {plan_path}")
        # Process response...
```markdown

**Key Insights:**

- **Planner Agent**: System prompt override + write hooks = constrained planning
- **Builder Agent**: Uses default Claude Code tools + `permission_mode="auto"`
- **Reviewer Agent**: Uses `append_system_prompt` to EXTEND, not override
- Template variables in system prompts via `{VARIABLE}` replacement
- Each agent has distinct model, tools, and hook configuration
- Sequential orchestration: Plan -> Build -> Review

### Pattern 6: Message Block Handling

**Common pattern across all agents:**

```python
async for message in client.receive_response():
    if isinstance(message, AssistantMessage):
        for block in message.content:
            if isinstance(block, TextBlock):
                # Agent's text response
                print(block.text)

            elif isinstance(block, ToolUseBlock):
                # Agent is calling a tool
                print(f"Tool: {block.name}")
                print(f"Input: {block.input}")

            elif isinstance(block, ToolResultBlock):
                # Tool execution result
                print(f"Result: {block.content}")

            elif isinstance(block, ThinkingBlock):
                # Agent's reasoning (if using extended thinking)
                print(f"Thinking: {block.thinking}")

    elif isinstance(message, ResultMessage):
        # End of agent turn
        print(f"Session ID: {message.session_id}")
        print(f"Duration: {message.duration_ms}ms")
        print(f"Cost: ${message.total_cost_usd:.6f}")
        print(f"Error: {message.is_error}")
```markdown

### Pattern 7: Tool Definition Best Practices

**From calculator agent:**

```python
@tool(
    "custom_math_evaluator",
    "Perform mathematical calculations",
    {"expression": str, "precision": int},
)
async def calculate_expression(args: dict[str, Any]) -> dict[str, Any]:
    """
    Tool implementation with error handling.

    Returns structured response:
    - Success: {"content": [{"type": "text", "text": result}]}
    - Error: {"content": [{"type": "text", "text": error_msg}], "is_error": True}
    """
    try:
        # Safe namespace for eval (security)
        allowed_functions = {
            name: func for name, func in math.__dict__.items()
            if not name.startswith("_")
        }

        result = eval(args["expression"], {"__builtins__": {}}, allowed_functions)
        precision = args.get("precision", 2)

        if isinstance(result, float):
            result = round(result, precision)

        return {
            "content": [{"type": "text", "text": f"Result: {result}"}]
        }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "is_error": True,
        }
```markdown

**Best Practices:**

- Descriptive tool names and descriptions
- Type hints in parameter spec
- Error handling with try/except
- Return structured response with `content` key
- Use `is_error` flag for error cases
- Provide default values for optional parameters
- Validate and sanitize inputs

### Pattern 8: Model Selection Strategy

**From various agents:**

```python
# Pong Agent: Simple response generation
model="claude-sonnet-4-20250514"  # Fast, good balance

# Echo Agent: Lightweight transformation
model="claude-3-5-haiku-20241022"  # Cheapest, fastest for simple tasks

# Calculator Agent: Moderate reasoning
model="claude-sonnet-4-20250514"  # Fast model for calculations

# QA Agent: Complex codebase analysis
model="claude-sonnet-4-20250514"  # Balance speed and quality

# SDLC Agents: Critical decision-making
model="claude-sonnet-4-20250514"  # or "claude-opus-4-..." for highest quality
```markdown

**Selection Criteria:**

- **Haiku**: Simple transformations, low-stakes decisions, high-volume operations
- **Sonnet**: Balanced performance, moderate complexity, most common choice
- **Opus**: Critical decisions, complex reasoning, quality over cost

> **Editor's Note (Dec 2025)**: Model identifiers shown above are from the course examples. Check [docs.anthropic.com/models](https://docs.anthropic.com/claude/docs/models) for current model IDs and availability.

### Common SDK Patterns Summary

| Pattern | Key Code | Use Case |
| ------- | -------- | -------- |
| **System Prompt Override** | `system_prompt=load_prompt()` | Complete custom behavior |
| **System Prompt Extend** | `append_system_prompt=load_prompt()` | Enhance Claude Code |
| **Custom Tools** | `@tool()` + `create_sdk_mcp_server()` | Domain-specific operations |
| **Session Continuity** | `resume=session_id` | Multi-turn conversations |
| **Inline Hooks** | `hooks={"PreToolUse": [...]}` | Permission control, auditing |
| **Tool Access Control** | `allowed_tools=[...]` or `disallowed_tools=[...]` | Security, focus |
| **Model Selection** | `model="claude-sonnet-4-..."` | Performance vs cost tradeoff |
| **One-Shot Query** | `query(prompt, options)` | Single request/response |
| **Multi-Turn Client** | `ClaudeSDKClient(options)` | Interactive sessions |
| **Message Processing** | `isinstance(message, AssistantMessage)` | Response handling |
| **Block Iteration** | `for block in message.content` | Extract text/tools/thinking |
| **Cost Tracking** | `ResultMessage.total_cost_usd` | Budget monitoring |

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 67:30 of content!)
- [x] Understood 8 agent patterns
- [x] Understood Claude Code SDK architecture
- [x] Understood Query vs Client pattern
- [x] Understood hooks for governance
- [x] Understood override vs append system prompt
- [x] Understood when to build custom vs use out-of-box
- [x] Explored companion repository (building-specialized-agents) - See patterns below
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 6**: One agent, one prompt, one purpose
- **Builds on Lesson 8**: Agentic layer with custom agents
- **Builds on Lesson 9**: Context engineering for agent efficiency
- **Builds on Lesson 10**: System prompt architecture
- **Sets up Lesson 12**: Custom agents for orchestration

## Notable Implementation Details

### Custom Tool Definition

```python
from claude_code import tool

@tool(
    name="calculate_expression",
    description="Perform mathematical calculations. Use for any math."
)
def calculate_expression(args: dict) -> dict:
    expression = args.get("expression", "")
    precision = args.get("precision", 2)
    try:
        result = eval(expression)  # Back in deterministic world
        return {
            "success": True,
            "result": round(result, precision)
        }
    except Exception as e:
        return {
            "success": False,
            "error": str(e)  # Let agent pivot
        }
```markdown

### Hook-Based Permission Control

```python
# Pre-tool-use hook to block sensitive files
def block_env_files(tool_name: str, args: dict) -> dict:
    if tool_name == "Read":
        path = args.get("file_path", "")
        if ".env" in path or "credentials" in path:
            return {
                "decision": "block",
                "reason": "Access to environment files blocked"
            }
    return {"decision": "allow"}
```markdown

### Session Continuity Pattern

```python
class AgentSession:
    def __init__(self):
        self.session_id = None
        self.client = ClaudeSdkClient(self._get_options())

    def _get_options(self):
        return ClaudeCodeOptions(
            system_prompt=self.system_prompt,
            model=self.model,
            resume=self.session_id  # Continue if exists
        )

    def query(self, prompt: str):
        response = self.client.query(prompt)
        for msg in response:
            if isinstance(msg, ResultMessage):
                self.session_id = msg.session_id
        return response
```yaml

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
