<!-- Source: https://docs.claude.com/en/docs/agent-sdk/python -->

# Agent SDK reference - Python

Complete API reference for the Python Agent SDK, including all functions, types, and classes.

## Installation

```bash  theme={null}
pip install claude-agent-sdk
```

## Choosing Between `query()` and `ClaudeSDKClient`

The Python SDK provides two ways to interact with Claude Code:

### Quick Comparison

| Feature             | `query()`                     | `ClaudeSDKClient`                  |
| :------------------ | :---------------------------- | :--------------------------------- |
| **Session**         | Creates new session each time | Reuses same session                |
| **Conversation**    | Single exchange               | Multiple exchanges in same context |
| **Connection**      | Managed automatically         | Manual control                     |
| **Streaming Input** | ✅ Supported                   | ✅ Supported                        |
| **Interrupts**      | ❌ Not supported               | ✅ Supported                        |
| **Hooks**           | ❌ Not supported               | ✅ Supported                        |
| **Custom Tools**    | ❌ Not supported               | ✅ Supported                        |
| **Continue Chat**   | ❌ New session each time       | ✅ Maintains conversation           |
| **Use Case**        | One-off tasks                 | Continuous conversations           |

### When to Use `query()` (New Session Each Time)

**Best for:**

* One-off questions where you don't need conversation history
* Independent tasks that don't require context from previous exchanges
* Simple automation scripts
* When you want a fresh start each time

### When to Use `ClaudeSDKClient` (Continuous Conversation)

**Best for:**

* **Continuing conversations** - When you need Claude to remember context
* **Follow-up questions** - Building on previous responses
* **Interactive applications** - Chat interfaces, REPLs
* **Response-driven logic** - When next action depends on Claude's response
* **Session control** - Managing conversation lifecycle explicitly

## Functions

### `query()`

Creates a new session for each interaction with Claude Code. Returns an async iterator that yields messages as they arrive. Each call to `query()` starts fresh with no memory of previous interactions.

```python  theme={null}
async def query(
    *,
    prompt: str | AsyncIterable[dict[str, Any]],
    options: ClaudeAgentOptions | None = None
) -> AsyncIterator[Message]
```

#### Parameters

| Parameter | Type                         | Description                                                                |
| :-------- | :--------------------------- | :------------------------------------------------------------------------- |
| `prompt`  | `str \| AsyncIterable[dict]` | The input prompt as a string or async iterable for streaming mode          |
| `options` | `ClaudeAgentOptions \| None` | Optional configuration object (defaults to `ClaudeAgentOptions()` if None) |

#### Returns

Returns an `AsyncIterator[Message]` that yields messages from the conversation.

#### Example - With options

```python  theme={null}

import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    options = ClaudeAgentOptions(
        system_prompt="You are an expert Python developer",
        permission_mode='acceptEdits',
        cwd="/home/user/project"
    )

    async for message in query(
        prompt="Create a Python web server",
        options=options
    ):
        print(message)


asyncio.run(main())
```

### `tool()`

Decorator for defining MCP tools with type safety.

```python  theme={null}
def tool(
    name: str,
    description: str,
    input_schema: type | dict[str, Any]
) -> Callable[[Callable[[Any], Awaitable[dict[str, Any]]]], SdkMcpTool[Any]]
```

#### Parameters

| Parameter      | Type                     | Description                                             |
| :------------- | :----------------------- | :------------------------------------------------------ |
| `name`         | `str`                    | Unique identifier for the tool                          |
| `description`  | `str`                    | Human-readable description of what the tool does        |
| `input_schema` | `type \| dict[str, Any]` | Schema defining the tool's input parameters (see below) |

#### Input Schema Options

1. **Simple type mapping** (recommended):

   ```python  theme={null}
   {"text": str, "count": int, "enabled": bool}
   ```

2. **JSON Schema format** (for complex validation):
   ```python  theme={null}
   {
       "type": "object",
       "properties": {
           "text": {"type": "string"},
           "count": {"type": "integer", "minimum": 0}
       },
       "required": ["text"]
   }
   ```

#### Returns

A decorator function that wraps the tool implementation and returns an `SdkMcpTool` instance.

#### Example

```python  theme={null}
from claude_agent_sdk import tool
from typing import Any

@tool("greet", "Greet a user", {"name": str})
async def greet(args: dict[str, Any]) -> dict[str, Any]:
    return {
        "content": [{
            "type": "text",
            "text": f"Hello, {args['name']}!"
        }]
    }
```

### `create_sdk_mcp_server()`

Create an in-process MCP server that runs within your Python application.

```python  theme={null}
def create_sdk_mcp_server(
    name: str,
    version: str = "1.0.0",
    tools: list[SdkMcpTool[Any]] | None = None
) -> McpSdkServerConfig
```

#### Parameters

| Parameter | Type                            | Default   | Description                                           |
| :-------- | :------------------------------ | :-------- | :---------------------------------------------------- |
| `name`    | `str`                           | -         | Unique identifier for the server                      |
| `version` | `str`                           | `"1.0.0"` | Server version string                                 |
| `tools`   | `list[SdkMcpTool[Any]] \| None` | `None`    | List of tool functions created with `@tool` decorator |

#### Returns

Returns an `McpSdkServerConfig` object that can be passed to `ClaudeAgentOptions.mcp_servers`.

#### Example

```python  theme={null}
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("add", "Add two numbers", {"a": float, "b": float})
async def add(args):
    return {
        "content": [{
            "type": "text",
            "text": f"Sum: {args['a'] + args['b']}"
        }]
    }

@tool("multiply", "Multiply two numbers", {"a": float, "b": float})
async def multiply(args):
    return {
        "content": [{
            "type": "text",
            "text": f"Product: {args['a'] * args['b']}"
        }]
    }

calculator = create_sdk_mcp_server(
    name="calculator",
    version="2.0.0",
    tools=[add, multiply]  # Pass decorated functions
)