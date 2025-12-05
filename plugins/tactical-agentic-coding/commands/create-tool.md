---
description: Generate custom tool boilerplate with @tool decorator for Claude Agent SDK
argument-hint: [tool-name] [description]
---

# Create Tool

Generate custom tool boilerplate with @tool decorator.

## Arguments

- `$1`: Tool name (snake_case)
- `$ARGUMENTS`: Tool description and purpose (after name)

## Instructions

You are creating a custom tool for use in custom agents.

### Step 1: Parse Arguments

Extract:

- Tool name from `$1` (required, snake_case)
- Description from remaining arguments

If no name provided, STOP and ask for tool name.
If no description provided, STOP and ask for tool purpose.

### Step 2: Identify Parameters

Based on the tool purpose, determine:

- What inputs does the tool need?
- Which are required vs optional?
- What types (str, int, float, bool)?

### Step 3: Generate Tool Definition

Create tool using @tool decorator:

```python
from typing import Any
from claude_agent_sdk import tool

@tool(
    "[tool_name]",
    "[Description for agent - when to use this tool]",
    {
        "param1": str,
        "param2": int,
    }
)
async def [tool_name](args: dict[str, Any]) -> dict[str, Any]:
    """
    [Brief docstring]
    """
    try:
        # Extract parameters
        param1 = args["param1"]
        param2 = args.get("param2", default_value)

        # Validate inputs
        if not param1:
            return {
                "content": [{"type": "text", "text": "Error: param1 required"}],
                "is_error": True
            }

        # Perform operation
        result = perform_operation(param1, param2)

        # Return success
        return {
            "content": [{"type": "text", "text": str(result)}]
        }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "is_error": True
        }
```

### Step 4: Generate MCP Server Setup

```python
from claude_agent_sdk import create_sdk_mcp_server

# Create server with tool
[server_name]_server = create_sdk_mcp_server(
    name="[server_name]",
    version="1.0.0",
    tools=[[tool_name]]
)
```

### Step 5: Generate Agent Configuration

```python
from claude_agent_sdk import ClaudeAgentOptions, ClaudeSDKClient

options = ClaudeAgentOptions(
    mcp_servers={"[server_name]": [server_name]_server},
    allowed_tools=["mcp__[server_name]__[tool_name]"],
    system_prompt=system_prompt,
    model="claude-sonnet-4-20250514",
)

# IMPORTANT: Use ClaudeSDKClient for custom tools
async with ClaudeSDKClient(options=options) as client:
    await client.query(prompt)
    async for message in client.receive_response():
        pass
```

## Output

```markdown
## Tool Created

**Name:** [tool_name]
**Server:** [server_name]
**Tool ID:** mcp__[server_name]__[tool_name]

### Tool Definition

```python
[Generated @tool decorated function]
```

### MCP Server

```python
[Generated server setup]
```

### Agent Configuration

```python
[Generated configuration]
```

### Parameters

| Name | Type | Required | Description |
| ------ | ------ | ---------- | ------------- |
| param1 | str | Yes | [description] |
| param2 | int | No | [description], default: [value] |

### Usage Example

Agent prompt: "[example prompt that triggers tool]"
Expected call: [tool_name](param1="value", param2=10)
Expected result: "[expected output]"

### Testing

```python
# Test the tool directly
result = await [tool_name]({"param1": "test", "param2": 10})
assert "content" in result
assert not result.get("is_error", False)
```

### Next Steps

1. Add tool to MCP server
2. Configure agent with tool access
3. Test tool in isolation
4. Test tool through agent

```text

## Notes

- See @tool-design skill for design workflow
- See @custom-tool-patterns.md for patterns
- CRITICAL: Use ClaudeSDKClient (not query()) for custom tools
