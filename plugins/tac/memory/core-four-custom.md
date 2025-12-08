# Core Four at Scale: Custom Agent Configuration

Control Context, Model, Prompt, and Tools for domain-specific agents.

## The Core Four Comparison

| Element | Out-of-Box | Custom Agent |
| --------- | ------------ | -------------- |
| **Context** | Generic CLAUDE.md | Domain-specific system prompt |
| **Model** | Default (Sonnet) | Task-appropriate (Haiku/Sonnet/Opus) |
| **Prompt** | User prompts only | Full system prompt control |
| **Tools** | 15+ default tools | Precise tool set |

## Context Control

### System Prompt Options

```python
# Option 1: Override (Create new product)
options = ClaudeAgentOptions(
    system_prompt=load_system_prompt("agent_system.md")
)

# Option 2: Extend (Enhance Claude Code)
options = ClaudeAgentOptions(
    append_system_prompt=load_system_prompt("extensions.md")
)
```markdown

**Warning**: Override = NOT Claude Code anymore. You've created a new product.

### External Prompt Files

```python
def load_system_prompt(filename: str) -> str:
    prompt_file = Path(__file__).parent / "prompts" / filename
    with open(prompt_file, "r") as f:
        return f.read().strip()
```markdown

## Model Selection

| Model | Use Case | Characteristics |
| ------- | ---------- | ----------------- |
| **Haiku** | Simple transformations, high-volume | Fastest, cheapest |
| **Sonnet** | Balanced performance, most tasks | Good speed/quality ratio |
| **Opus** | Complex reasoning, critical decisions | Highest quality, slowest |

```python
# Simple task
options = ClaudeAgentOptions(model="claude-3-5-haiku-20241022")

# Balanced task
options = ClaudeAgentOptions(model="claude-sonnet-4-20250514")

# Complex task
options = ClaudeAgentOptions(model="claude-opus-4-20250514")
```markdown

## Prompt Control

### System Prompt Architecture

**Simple Agent (Single Purpose):**

```markdown
# Agent Name
## Purpose
You are [identity]. Your single task is [task].
```markdown

**Complex Agent (Multi-Step Workflow):**

```markdown
# Agent Name
## Purpose
You are [identity] specializing in [domain].

## Instructions
### Core Behaviors
- Behavior 1
- Behavior 2

### Workflow
1. Step 1
2. Step 2
3. Step 3

### Examples
[Input/Output pairs]
```markdown

## Tools Control

### Token Overhead Warning

> "15 extra tools consume space in your agent's mind. Use /context to understand what's going into your agent."

Default Claude Code includes 15+ tools. Each tool definition consumes context window space even if never used.

### Tool Access Patterns

```python
# Whitelist specific tools
options = ClaudeAgentOptions(
    allowed_tools=["Read", "Write", "Bash"]
)

# Blacklist unwanted tools
options = ClaudeAgentOptions(
    disallowed_tools=[
        "WebFetch", "WebSearch", "TodoWrite", "Task"
    ]
)

# Combine for precision
options = ClaudeAgentOptions(
    allowed_tools=[
        "mcp__calculator__evaluate",
        "mcp__calculator__convert"
    ],
    disallowed_tools=[
        "Read", "Write", "Edit", "Bash", "Glob", "Grep"
    ]
)

# Disable all default tools
options = ClaudeAgentOptions(
    disallowed_tools=["*"]
)
```markdown

### Custom Tool Integration

```python
# Create MCP server with custom tools
server = create_sdk_mcp_server(
    name="my_tools",
    version="1.0.0",
    tools=[tool1, tool2]
)

options = ClaudeAgentOptions(
    mcp_servers={"my_tools": server},
    allowed_tools=["mcp__my_tools__tool1", "mcp__my_tools__tool2"]
)
```markdown

## Configuration Template

```python
options = ClaudeAgentOptions(
    # Context: Domain-specific system prompt
    system_prompt=load_system_prompt("domain_agent.md"),

    # Model: Task-appropriate selection
    model="opus",

    # Tools: Precise set
    mcp_servers={"domain": domain_mcp_server},
    allowed_tools=["mcp__domain__specialized_tool"],
    disallowed_tools=["WebFetch", "WebSearch", "TodoWrite"],

    # Governance: Permission hooks
    hooks={"PreToolUse": [security_hook]},

    # Session: Continuity
    resume=session_id,
)
```markdown

## Key Insights

1. **Context**: Override for custom products, append for extensions
2. **Model**: Match model capability to task complexity
3. **Prompt**: Version control all system prompts
4. **Tools**: Strip unnecessary tools for focused agents

## Cross-References

- @agent-evolution-path.md - When to move to custom agents
- @system-prompt-architecture.md - Override vs append patterns
- @custom-tool-patterns.md - Tool creation patterns
- @model-selection skill - Detailed model selection guidance
