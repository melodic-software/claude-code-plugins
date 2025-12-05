# Custom Tool Patterns

Create domain-specific tools for custom agents using the @tool decorator.

## Basic Tool Definition

```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool(
    "tool_name",                          # Tool identifier
    "Human-readable description",          # How agent uses it
    {"param1": str, "param2": int},       # Parameter schema
)
async def my_tool(args: dict) -> dict:
    """Tool implementation"""
    param1 = args["param1"]
    param2 = args.get("param2", default_value)

    result = do_something(param1, param2)

    return {"content": [{"type": "text", "text": result}]}
```markdown

## Tool Naming Convention

```

mcp__{server_name}__{tool_name}

Examples:

- mcp__calculator__evaluate
- mcp__echo__transform
- mcp__database__query

```markdown

## Return Format

### Success Response

```python
return {
    "content": [
        {"type": "text", "text": "Result: 42"}
    ]
}
```markdown

### Error Response

```python
return {
    "content": [
        {"type": "text", "text": "Error: Division by zero"}
    ],
    "is_error": True
}
```markdown

## Complete Tool Example

```python
@tool(
    "calculate_expression",
    "Evaluate mathematical expressions safely",
    {"expression": str, "precision": int},
)
async def calculate_expression(args: dict) -> dict:
    try:
        # Safe namespace
        allowed_functions = {
            name: func for name, func in math.__dict__.items()
            if not name.startswith("_")
        }

        expression = args["expression"]
        precision = args.get("precision", 2)

        result = eval(expression, {"__builtins__": {}}, allowed_functions)

        if isinstance(result, float):
            result = round(result, precision)

        return {
            "content": [{"type": "text", "text": f"Result: {result}"}]
        }

    except Exception as e:
        return {
            "content": [{"type": "text", "text": f"Error: {str(e)}"}],
            "is_error": True
        }
```markdown

## MCP Server Creation

```python
# Create server with multiple tools
calculator_server = create_sdk_mcp_server(
    name="calculator",
    version="1.0.0",
    tools=[
        calculate_expression,
        convert_units,
        format_number,
    ]
)

# Configure agent with server
options = ClaudeAgentOptions(
    mcp_servers={"calculator": calculator_server},
    allowed_tools=[
        "mcp__calculator__calculate_expression",
        "mcp__calculator__convert_units",
        "mcp__calculator__format_number",
    ],
    system_prompt=system_prompt,
    model="claude-sonnet-4-20250514",
)
```markdown

## Critical: Client vs Query

> **Warning**: Custom tools require `ClaudeSDKClient`, not `query()`

```python
# WRONG - query() doesn't support custom tools
async for message in query(prompt, options=options):
    pass

# CORRECT - Use ClaudeSDKClient for custom tools
async with ClaudeSDKClient(options=options) as client:
    await client.query(prompt)
    async for message in client.receive_response():
        pass
```markdown

## Tool Design Best Practices

### 1. Descriptive Names and Descriptions

```python
# Good - Clear purpose
@tool("calculate_compound_interest",
      "Calculate compound interest given principal, rate, time, and frequency")

# Bad - Vague
@tool("calc", "Does calculations")
```markdown

### 2. Typed Parameters

```python
@tool(
    "process_data",
    "Process data with options",
    {
        "data": str,           # Required string
        "format": str,         # Required string
        "limit": int,          # Required integer
        "verbose": bool,       # Required boolean
    }
)
```markdown

### 3. Default Values

```python
async def my_tool(args: dict) -> dict:
    required_param = args["required_param"]     # Must exist
    optional_param = args.get("optional", 10)   # Default to 10
```markdown

### 4. Error Handling

```python
async def my_tool(args: dict) -> dict:
    try:
        # Validate inputs
        if not args.get("required"):
            return error_response("Missing required parameter")

        # Process
        result = process(args)
        return success_response(result)

    except ValueError as e:
        return error_response(f"Invalid input: {e}")
    except Exception as e:
        return error_response(f"Unexpected error: {e}")
```markdown

### 5. Input Validation

```python
async def my_tool(args: dict) -> dict:
    # Validate and sanitize
    expression = args.get("expression", "")

    # Security check
    if any(danger in expression for danger in ["import", "exec", "eval"]):
        return error_response("Security: Dangerous operation blocked")

    # Type check
    if not isinstance(expression, str):
        return error_response("Type error: expression must be string")
```markdown

## Tool Categories

### Data Processing Tools

```python
@tool("parse_json", "Parse JSON string to structured data", {"json_str": str})
@tool("format_output", "Format data for display", {"data": str, "format": str})
```markdown

### Integration Tools

```python
@tool("query_database", "Execute database query", {"query": str, "params": str})
@tool("call_api", "Make API request", {"endpoint": str, "method": str})
```markdown

### Domain Tools

```python
@tool("analyze_code", "Analyze code for patterns", {"code": str, "language": str})
@tool("validate_schema", "Validate data against schema", {"data": str, "schema": str})
```markdown

## Key Insight

> "Tools are built with @tool decorator. The description tells your agent how to use the tool."

The description is critical - it's how the agent knows when and how to use your tool.

## Cross-References

- @core-four-custom.md - Tools as part of Core Four
- @tool-design skill - Workflow for creating tools
- @agent-governance.md - Hooks for tool access control
