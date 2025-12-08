---
name: tool-design
description: Create custom tools using the @tool decorator for domain-specific agents. Use when building agent-specific tools, implementing MCP servers, or creating in-memory tools with the Agent SDK.
version: 1.0.0
allowed-tools: Read, Grep, Glob
tags: [tool, decorator, MCP, custom, in-memory, SDK]
---

# Tool Design Skill

Create custom tools for domain-specific agents using the @tool decorator.

## Purpose

Design and implement custom tools that give agents specialized capabilities for domain-specific operations.

## When to Use

- Agent needs capabilities beyond default tools
- Domain requires specialized operations
- Building focused, efficient agents
- Creating reusable tool libraries

## Prerequisites

- Understanding of @tool decorator syntax
- Knowledge of MCP server creation
- Clear definition of tool purpose

## Design Process

### Step 1: Define Tool Purpose

Answer:

- What operation does this tool perform?
- What inputs does it need?
- What output does it produce?
- When should the agent use this tool?

### Step 2: Design Tool Interface

**Tool Signature**:

```python
@tool(
    "tool_name",                    # Unique identifier
    "Description for agent",        # How agent knows when to use
    {"param1": type, "param2": type}  # Parameter schema
)
async def tool_implementation(args: dict) -> dict:
    pass
```markdown

**Naming Convention**:

- Use snake_case for tool names
- Be descriptive: `calculate_compound_interest` not `calc`
- Prefix with domain: `db_query`, `api_call`

**Description Guidelines**:

- Explain WHEN to use the tool
- Explain WHAT it does
- Include any constraints

### Step 3: Define Parameters

**Parameter Types**:

```python
{
    "text_param": str,      # String
    "number_param": int,    # Integer
    "decimal_param": float, # Float
    "flag_param": bool,     # Boolean
}
```markdown

**Required vs Optional**:

```python
async def my_tool(args: dict) -> dict:
    # Required - must exist
    required = args["required_param"]

    # Optional - with default
    optional = args.get("optional_param", "default")
```markdown

### Step 4: Implement Tool Logic

**Basic Template**:

```python
@tool(
    "tool_name",
    "Description",
    {"param1": str, "param2": int}
)
async def tool_name(args: dict) -> dict:
    try:
        # 1. Extract and validate inputs
        param1 = args["param1"]
        param2 = args.get("param2", 10)

        # 2. Perform operation
        result = perform_operation(param1, param2)

        # 3. Return success
        return {
            "content": [{"type": "text", "text": str(result)}]
        }

    except Exception as e:
        # 4. Handle errors
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "is_error": True
        }
```markdown

### Step 5: Add Error Handling

**Validation Pattern**:

```python
async def my_tool(args: dict) -> dict:
    # Validate required params
    if "required" not in args:
        return error_response("Missing required parameter")

    # Validate types
    if not isinstance(args["required"], str):
        return error_response("Parameter must be string")

    # Validate values
    if args.get("limit", 0) < 0:
        return error_response("Limit cannot be negative")

    # Security validation
    if is_dangerous(args["input"]):
        return error_response("Security: Operation blocked")
```markdown

**Error Response Helper**:

```python
def error_response(message: str) -> dict:
    return {
        "content": [{"type": "text", "text": message}],
        "is_error": True
    }

def success_response(result: str) -> dict:
    return {
        "content": [{"type": "text", "text": result}]
    }
```markdown

### Step 6: Create MCP Server

```python
from claude_agent_sdk import create_sdk_mcp_server

# Create server with tools
my_server = create_sdk_mcp_server(
    name="my_domain",
    version="1.0.0",
    tools=[
        tool_one,
        tool_two,
        tool_three,
    ]
)
```markdown

### Step 7: Configure Agent

```python
options = ClaudeAgentOptions(
    mcp_servers={"my_domain": my_server},
    allowed_tools=[
        "mcp__my_domain__tool_one",
        "mcp__my_domain__tool_two",
        "mcp__my_domain__tool_three",
    ],
    # Disable unused default tools
    disallowed_tools=["WebFetch", "WebSearch", "TodoWrite"],
    system_prompt=system_prompt,
    model="opus",
)
```markdown

## Tool Categories

### Data Processing Tools

```python
@tool("parse_json", "Parse JSON string", {"json_str": str})
@tool("transform_data", "Transform data format", {"data": str, "format": str})
@tool("validate_schema", "Validate against schema", {"data": str, "schema": str})
```markdown

### Domain Operation Tools

```python
@tool("calculate_metric", "Calculate business metric", {"values": str, "metric": str})
@tool("lookup_reference", "Look up reference data", {"key": str})
@tool("process_record", "Process domain record", {"record": str})
```markdown

### Integration Tools

```python
@tool("query_database", "Execute DB query", {"query": str})
@tool("call_api", "Call external API", {"endpoint": str, "method": str})
@tool("send_notification", "Send notification", {"channel": str, "message": str})
```markdown

## Output Format

When designing a tool:

```markdown
## Tool Design

**Name:** [tool_name]
**Purpose:** [what it does]
**Domain:** [where it's used]

### Interface

```python
@tool(
    "tool_name",
    "Description for agent usage",
    {"param1": str, "param2": int}
)
```markdown

### Parameters

| Name | Type | Required | Description |
| ------ | ------ | ---------- | ------------- |
| param1 | str | Yes | [description] |
| param2 | int | No | [description], default: 10 |

### Return Format

**Success:**

```json
{"content": [{"type": "text", "text": "[result format]"}]}
```markdown

**Error:**

```json
{"content": [{"type": "text", "text": "Error: [message]"}], "is_error": true}
```markdown

### Implementation

```python
[Full implementation code]
```markdown

### Usage Example

Agent prompt: "[example prompt that uses tool]"
Tool call: tool_name(param1="value", param2=20)
Result: "[expected result]"

```

## Design Checklist

- [ ] Tool name is descriptive
- [ ] Description explains when to use
- [ ] Parameter types are defined
- [ ] Required vs optional is clear
- [ ] Input validation is complete
- [ ] Error handling is robust
- [ ] Security checks are in place
- [ ] Return format is consistent

## Critical: Client vs Query

> **Warning**: Custom tools require `ClaudeSDKClient`, not `query()`

```python
# WRONG
async for message in query(prompt, options=options):
    pass

# CORRECT
async with ClaudeSDKClient(options=options) as client:
    await client.query(prompt)
    async for message in client.receive_response():
        pass
```markdown

## Cross-References

- @custom-tool-patterns.md - Tool creation patterns
- @core-four-custom.md - Tools in Core Four
- @custom-agent-design skill - Agent design workflow
