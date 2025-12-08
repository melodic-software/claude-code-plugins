# The Core Four Framework

The Core Four is the foundational framework for Agentic Coding, introduced in TAC Lesson 001.

## From Big Three to Core Four

### The Big Three (AI Coding - Phase 1)

AI coding operates with three elements:

| Element | Description |
| --------- | ------------- |
| **Context** | What the model sees (files, conversation history) |
| **Model** | The reasoning engine (Claude, GPT, etc.) |
| **Prompt** | The instructions you provide |

This is the principle of AI coding. It's always there, even if you can't see it.

### The Core Four (Agentic Coding - Phase 2)

Agentic coding expands the Big Three by adding one crucial element:

| Element | Description | Examples |
| --------- | ------------- | ---------- |
| **Context** | What the agent sees | CLAUDE.md, loaded files, conversation history |
| **Model** | The reasoning engine | Claude Sonnet, Opus, Haiku |
| **Prompt** | The instructions | System prompt, user prompt, agentic prompts |
| **Tools** | Agent capabilities | Read, Write, Bash, MCP servers, web access |

## Why Tools Change Everything

Tool calling has existed for years. What's different now?

**It's not a question of new. It's a question of scale and performance.**

Claude Code is the first agentic coding tool to properly combine three essential elements:

1. A powerful language model that can reason when needed
2. The ability to consistently call **long chains of tools**
3. The right agent architecture

This combination unlocks reliable agentic coding at scale - something not possible before.

## The Agentic Prompt

The new primitive: **prompts that can reliably execute long chains of tools.**

People call these "just prompts" - but don't turn your brain off. The scale at which the Core Four and the agentic prompt changes engineering work is massive.

**Key insight:** With the Core Four wrapped in an agentic coding tool like Claude Code, you can create long-running end-to-end AI developer workflows that run for minutes to hours with and without your oversight.

## AI Coding vs Agentic Coding Example

### AI Coding Prompt (Phase 1)

```markdown
CREATE main_aic.py:
    print "goodbye ai coding"
```markdown

Single-action code generation. Simple, but limited.

### Agentic Coding Prompt (Phase 2)

```markdown
RUN:
    checkout a new/existing "demo-agentic-coding" git branch

CREATE main_tac.py:
    print "hello agentic coding"
    print a concise explanation of the definition of ai agents

RUN:
    uv run main_tac.py
    git add .
    git commit -m "Demo agentic coding capabilities"

REPORT:
    respond with the exact output of the .py file
```yaml

Multi-step workflow with tool calls, planning, validation, and version control.

## The Core Four Elements in Detail

### Context

What the agent can see and use:

- **CLAUDE.md files** - Project instructions, conventions, memory
- **Loaded files** - Code, documentation, configuration
- **Conversation history** - Previous messages and tool results
- **MCP resources** - External data sources

### Model

The reasoning engine:

- **Claude Opus** - Maximum capability, complex reasoning
- **Claude Sonnet** - Balanced speed and capability
- **Claude Haiku** - Fast, cost-effective for simpler tasks

### Prompt

The instructions that drive behavior:

- **System prompt** - Core instructions and persona
- **User prompt** - Specific task requests
- **Agentic prompts** - Multi-step workflows with tool sequences

### Tools

Capabilities that enable action:

- **Read/Write/Edit** - File system operations
- **Bash** - Command execution
- **Grep/Glob** - Search and discovery
- **MCP servers** - External integrations (databases, APIs, services)
- **WebFetch/WebSearch** - Internet access

## Related

- @tac-philosophy.md - Core TAC philosophy and mindset
- @programmable-claude-patterns.md - Running Claude Code programmatically

---

**Source:** Lesson 001 - Hello Agentic Coding
**Last Updated:** 2025-12-04
