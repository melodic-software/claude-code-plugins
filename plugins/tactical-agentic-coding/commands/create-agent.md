---
description: Scaffold a new custom agent configuration with Claude Agent SDK patterns
argument-hint: [agent-name] [purpose-description]
---

# Create Agent

Scaffold a new custom agent configuration.

## Arguments

- `$1`: Agent name (kebab-case)
- `$ARGUMENTS`: High-level purpose description (after name)

## Instructions

You are creating a new custom agent scaffold using Claude Agent SDK patterns.

### Step 1: Parse Arguments

Extract:

- Agent name from `$1` (required)
- Purpose from remaining arguments

If no name provided, STOP and ask for agent name.
If no purpose provided, STOP and ask for purpose description.

### Step 2: Design Agent

Based on the purpose, determine:

**Model Selection:**

- Simple transformations -> Haiku
- Balanced tasks -> Sonnet
- Complex reasoning -> Opus

**System Prompt Architecture:**

- Building new product -> Override
- Extending Claude Code -> Append

**Tool Requirements:**

- What tools needed?
- What tools should be blocked?
- Any custom tools required?

### Step 3: Generate System Prompt

Create system prompt following structure:

```markdown
# [Agent Name]

## Purpose

[Identity and role - 2-3 sentences]

## Instructions

[Core behaviors - bullet list]

## Constraints

[What agent must NOT do]

## Examples (if needed)

[Input/Output pairs]
```

### Step 4: Generate Configuration

Create ClaudeAgentOptions configuration:

```python
from claude_agent_sdk import ClaudeAgentOptions

def load_system_prompt() -> str:
    prompt_file = Path(__file__).parent / "prompts" / "[agent]_system.md"
    with open(prompt_file, "r") as f:
        return f.read().strip()

options = ClaudeAgentOptions(
    system_prompt=load_system_prompt(),
    model="claude-[model]-...",
    allowed_tools=[...],
    disallowed_tools=[...],
)
```

### Step 5: Generate Entry Point

Create basic agent script:

```python
import asyncio
from pathlib import Path
from claude_agent_sdk import (
    query,
    ClaudeAgentOptions,
    AssistantMessage,
    TextBlock,
    ResultMessage,
)

async def main():
    options = ClaudeAgentOptions(...)

    prompt = input("Enter prompt: ")

    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    print(block.text)
        elif isinstance(message, ResultMessage):
            print(f"Cost: ${message.total_cost_usd:.6f}")

if __name__ == "__main__":
    asyncio.run(main())
```

## Output

```markdown
## Agent Created

**Name:** [agent-name]
**Model:** [haiku/sonnet/opus]
**Architecture:** [override/append]

### Files to Create

1. `[agent-name]/prompts/[agent]_system.md` - System prompt
2. `[agent-name]/[agent]_agent.py` - Agent implementation
3. `[agent-name]/README.md` - Documentation

### System Prompt

```markdown
[Generated system prompt]
```

### Configuration

```python
[Generated configuration]
```

### Entry Point

```python
[Generated script]
```

### Next Steps

1. Create the directory structure
2. Save the system prompt
3. Save the agent script
4. Test with simple prompt
5. Add custom tools if needed
6. Add governance hooks if needed

```

## Notes

- See @custom-agent-design skill for design workflow
- See @core-four-custom.md for configuration options
- See @system-prompt-architecture.md for prompt patterns
