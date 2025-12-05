# System Prompt Architecture

Patterns for controlling agent behavior through system prompts.

## The Critical Warning

> "When you override the system prompt, this is NOT Claude Code anymore. You've created a new product entirely."

The system prompt is your most important element with zero exceptions. Touch it, and you change the product.

## Two Approaches

### 1. Override Pattern

**Use when**: Building true custom agents with unique behavior

```python
options = ClaudeAgentOptions(
    system_prompt=load_system_prompt("custom_agent.md")
)
```markdown

**Characteristics**:

- Complete behavior replacement
- No Claude Code defaults
- Full control over identity
- You define all rules
- Not Claude Code anymore

**Example System Prompt (Override)**:

```markdown
# Custom Agent

## Purpose
You are a specialized [domain] agent. Your role is [specific purpose].

## Instructions
- Rule 1
- Rule 2
- Rule 3

## Constraints
- What you must NOT do
- Boundaries

## Examples
[Input/Output pairs showing expected behavior]
```markdown

### 2. Append Pattern

**Use when**: Extending Claude Code with additional capabilities

```python
options = ClaudeAgentOptions(
    append_system_prompt=load_system_prompt("extensions.md")
)
```markdown

**Characteristics**:

- Adds to Claude Code behavior
- Preserves default capabilities
- Enhances, doesn't replace
- Good for focused additions
- Still Claude Code at core

**Example System Prompt (Append)**:

```markdown
## Additional Context

When working in this codebase:
- Follow [specific patterns]
- Use [specific tools]
- Report in [specific format]

## Domain Knowledge

[Specialized knowledge for this domain]
```markdown

## Decision Framework

| Scenario | Pattern | Reason |
| ---------- | --------- | -------- |
| Building a calculator | Override | Pure custom behavior |
| Adding code review rules | Append | Enhance existing |
| Creating a QA bot | Override | Specialized purpose |
| Adding security guidelines | Append | Extend safety |
| Building a data processor | Override | Domain-specific |
| Adding codebase context | Append | More context |

## System Prompt Structure

### Minimal (Simple Agent)

```markdown
# Agent Name

## Purpose
One paragraph defining identity and purpose.
```markdown

### Standard (Focused Agent)

```markdown
# Agent Name

## Purpose
Identity and primary purpose.

## Instructions
- Core behavior 1
- Core behavior 2
- Core behavior 3

## Constraints
- What not to do
```markdown

### Comprehensive (Complex Agent)

```markdown
# Agent Name

## Purpose
Detailed identity and expertise description.

## Variables
VARIABLE_NAME: {VALUE}

## Instructions

### Core Behaviors
- Behavior category 1
- Behavior category 2

### Workflow
1. Step 1
2. Step 2
3. Step 3

### Edge Cases
- Handle case A by...
- Handle case B by...

## Constraints
- Security rules
- Boundary definitions

## Examples

### Example 1: [Scenario]
**Input:** [example input]
**Output:** [expected output]

### Example 2: [Edge Case]
**Input:** [edge case input]
**Output:** [handling output]
```markdown

## Variable Substitution

For dynamic system prompts:

```python
def load_prompt(path: str, variables: dict) -> str:
    with open(path, "r") as f:
        content = f.read()

    for key, value in variables.items():
        content = content.replace(f"{{{key}}}", str(value))

    return content

# Usage
system_prompt = load_prompt(
    "prompts/planner.md",
    {
        "TICKET_TITLE": ticket.title,
        "PLAN_DIRECTORY": "plans/"
    }
)
```markdown

## File Organization

```

project/
├── prompts/
│   ├── AGENT_NAME_SYSTEM_PROMPT.md    # Main system prompt
│   ├── TASK_SPECIFIC_PROMPT.md        # Task variations
│   └── EXTENSIONS.md                   # Append content

```markdown

## Version Control Best Practices

1. **Store prompts as files** - Not inline strings
2. **Use semantic versioning** - Track prompt evolution
3. **Document changes** - Why prompts changed
4. **Test prompts** - Validate behavior changes
5. **Review prompts** - Treat like code

## Key Quotes

> "The system prompt is the most important element of your custom agents, with zero exceptions."

> "Touch the system prompt, and you change the product entirely."

## Cross-References

- @core-four-custom.md - Full Core Four control
- @system-vs-user-prompts.md - System vs user distinction
- @custom-agent-design skill - Agent design workflow
