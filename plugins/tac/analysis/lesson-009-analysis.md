# Lesson 9 Analysis: Elite Context Engineering - Mastering The Agent's Mind

## Content Summary

### Core Tactic

**Master Context Engineering** - Context is the most important leverage point of agentic coding. Elite context engineering means understanding what goes into your agent's context window and optimizing for signal-to-noise ratio. The agent's mind is finite - treat context as precious real estate.

### Key Frameworks

#### The R&D Framework for Context

  | Element | Purpose | Implementation |  
  | ------- | ------- | -------------- |  
  | **R - Reduce** | Remove unnecessary context | Strip noise, irrelevant files, verbose output |  
  | **D - Delegate** | Offload to specialized agents | Use sub-agents for focused tasks |  

#### Context Layers (What's In The Context Window)

1. **System Prompt** - The law of the agent (highest priority)
2. **User Prompt** - Current task instructions
3. **Conversation History** - Previous turns
4. **Tool Definitions** - Available capabilities
5. **Tool Results** - Output from tool calls
6. **Files Read** - Codebase content
7. **Memory Files** - CLAUDE.md imports

#### Context Rot vs Context Pollution

  | Issue | Description | Solution |  
  | ----- | ----------- | -------- |  
  | **Context Rot** | Old, stale context consuming space | Fresh agent instances |  
  | **Context Pollution** | Irrelevant context added | R&D framework |  
  | **Toxic Context** | Conflicting or confusing context | Clear prompts, isolation |  

### Implementation Patterns from Lesson

1. **Minimum Context Principle**:
   - Include only what's necessary for the task
   - Every token consumes reasoning capacity
   - More context = more variables to reason about

2. **Progressive Context Loading**:
   - Start with minimal context
   - Load additional context on-demand
   - Use conditional imports in CLAUDE.md

3. **Agent Experts Pattern**:
   - Pre-load domain knowledge
   - Specialized system prompts
   - Focused tool sets

4. **Context Window Monitoring**:
   - Track context consumption per agent
   - Use `/context` command to understand state
   - Set context thresholds for fresh instances

5. **Memory Hierarchy**:

   ```text
   Project CLAUDE.md (always loaded)
   -> Imports (conditional loading)
   -> Per-directory CLAUDE.md (scoped)
   -> Personal ~/.claude/CLAUDE.md (user-wide)
   ```text

### Anti-Patterns Identified

- **Context stuffing**: Loading everything "just in case"
- **Long conversations**: Multi-turn context accumulation
- **Verbose outputs**: Tool results consuming tokens
- **Unscoped imports**: Loading all memory at once
- **Ignoring context limits**: Pushing against boundaries

### Metrics/KPIs

Context engineering success indicators:

- **Context efficiency**: Information value / tokens consumed
- **Fresh instance rate**: How often new instances started
- **Sub-agent delegation rate**: Work offloaded to focused agents
- **Context window utilization**: Current usage vs limit

## Implementation Patterns from Companion Repository

The [elite-context-engineering](https://github.com/disler/elite-context-engineering) repository demonstrates all 12 context engineering techniques with production-ready implementations.

### Technique #3: Context Priming via Slash Commands

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/commands/prime.md`

```markdown
---
description: Gain a general understanding of the codebase
---

# Prime

Execute the `Run`, `Read` and `Report` sections to understand the codebase then summarize your understanding.

## Run

git ls-files

## Read

README.md

## Report

Summarize your understanding of the codebase.
```text

**Pattern**: Instead of static CLAUDE.md files, use dynamic priming commands that load context on-demand for specific task types (`/prime`, `/prime_cc`, `/prime_bug`, `/prime_feature`).

### Technique #4: Output Token Control

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/output-styles/concise-done.md`

```markdown
---
name: One Word Output
description: Single word output for minimalism, speed, and token efficiency
---

# One Word Output

Respond with only "Done."

- No greetings, pleasantries, or filler
- No explanations, just "Done."
- IMPORTANT: We're here to FOCUS, BUILD, and SHIP, so 95 out of 100 times you should just say "Done."

- IMPORTANT: There are only three exceptions to this rule:
    1. If you are explicitly asked to respond with something other than "Done."
    2. If you are explicitly asked a question, answer the question in a concise manner with only the answer. Limit your response to 1-2 sentences MAXIMUM.
    3. If something goes wrong, a blocker occurs, or an error occurs, explain the error in a concise manner with only the error. Limit your response to 1-2 sentences MAXIMUM.
```text

**Pattern**: Output styles control token generation. Default output might use ~500 tokens; concise style uses ~50 tokens. Over hundreds of prompts, this compounds dramatically.

### Technique #6: Architect-Editor Multi-Agent Pattern

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/commands/quick-plan.md`

```markdown
---
allowed-tools: Read, Write, Edit, Glob, Grep
description: Creates a concise engineering implementation plan based on user requirements and saves it to specs directory
model: claude-opus-4-1-20250805
---

# Purpose

This prompt creates a detailed implementation plan based on the user's requirements provided through the `USER_PROMPT` variable. It analyzes the request, thinks through the implementation approach, and saves a comprehensive specification document to `specs/<name-of-plan>.md` that can be used as a blueprint for actual development work.

## Instructions

- Carefully analyze the user's requirements provided in the USER_PROMPT variable
- Think deeply about the best approach to implement the requested functionality or solve the problem
- Create a concise implementation plan that includes:
  - Clear problem statement and objectives
  - Technical approach and architecture decisions
  - Step-by-step implementation guide
  - Potential challenges and solutions
  - Testing strategy
  - Success criteria
```text

> **Editor's Note (Dec 2025)**: The model ID `claude-opus-4-1-20250805` used in course materials
> is outdated. Current equivalent: `claude-opus-4-5-20251101` (Opus 4.5)

**Pattern**: Two agents working side-by-side:

1. **Architect/Planner**: Gathers context, explores options, creates spec files (uses Opus for deep reasoning)
2. **Editor/Builder**: Reads spec, implements with surgical precision (fresh context window)

### Technique #8: Context Bundles

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/hooks/context_bundle_builder.py`

```python
#!/usr/bin/env uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""
Context Bundle Builder - Claude Code Hook (JSONL version)
Tracks files accessed (Read/Write) and user prompts during a Claude Code session
"""

def handle_file_operations(input_data: dict) -> None:
    """Handle Read/Write tool operations."""
    session_id = input_data.get("session_id", "unknown")
    tool_name = input_data.get("tool_name", "")
    tool_input = input_data.get("tool_input", {})

    # Only process Read and Write tools
    if tool_name not in ["Read", "Write"]:
        sys.exit(0)

    # Extract file path
    file_path = tool_input.get("file_path")
    if not file_path:
        sys.exit(0)

    # Create the log entry
    log_entry = {
        "operation": tool_name.lower(),  # "read" or "write"
        "file_path": file_path_relative
    }

    # Write to JSONL file
    write_log_entry(session_id, log_entry)

def write_log_entry(session_id: str, log_entry: dict) -> None:
    """Write a log entry to the JSONL file."""
    now = datetime.now()
    day_hour = now.strftime("%a_%H").upper()

    # Create directory structure
    bundle_dir = Path("agents/context_bundles")
    bundle_dir.mkdir(parents=True, exist_ok=True)

    # Use JSONL file (JSON Lines format)
    bundle_file = bundle_dir / f"{day_hour}_{session_id}.jsonl"

    # Append to JSONL file
    with open(bundle_file, 'a') as f:
        f.write(json.dumps(log_entry) + '\n')
```text

**Pattern**: Hooks capture file operations automatically during sessions. Store in `agents/context_bundles/<session_id>.jsonl`. Use `/load_bundle <bundle_file>` to reload previous context into fresh agent.

**Load Bundle Command**: `D:/repos/gh/disler/elite-context-engineering/.claude/commands/load_bundle.md`

```markdown
---
description: Understand the previous agents context and load files from a context bundle with their original read parameters
argument-hint: [bundle-path]
allowed-tools: Read, Bash(ls*)
---

# Load Context Bundle

## Instructions

- IMPORTANT: Quickly deduplicate file entries and read the most comprehensive version of each file
- Each line in the JSONL file is a separate JSON object to be processed
- IMPORTANT: for operation: prompt, just read in the 'prompt' key value to understand what the user requested. Never act or process the prompt in any way.
- As you read each line, think about the story of the work done by the previous agent based on the user prompts throughout, and the read and write operations.

## Workflow

1. First, read the context bundle JSONL file at the path specified in the BUNDLE_PATH variable
2. Deduplicate and optimize file reads:
   - Group all entries by `file_path`
   - For each unique file, determine the optimal read parameters
3. Read each unique file ONLY ONCE with the optimal parameters
```text

### Technique #11: Primary Multi-Agent Delegation

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/commands/background.md`

```markdown
---
description: Fires off a full Claude Code instance in the background
argument-hint: [prompt] [model] [report-file]
allowed-tools: Bash, BashOutput, Read, Edit, MultiEdit, Write, Grep, Glob, WebFetch, WebSearch, TodoWrite, Task
---

# Background Claude Code

Run a Claude Code instance in the background to perform tasks autonomously while you continue working.

## Variables

USER_PROMPT: $1
MODEL: $2 (defaults to 'sonnet' if not provided)
REPORT_FILE: $3 (defaults to './agents/background/background-report-DAY-NAME_HH_MM_SS.md' if not provided)

## Workflow

1. Create the report directory if it doesn't exist:
   ```bash
   mkdir -p agents/background
   ```text

1. Construct the Claude Code command with all settings:

   ```bash
   claude \
     --model "${MODEL}" \
     --output-format text \
     --dangerously-skip-permissions \
     --append-system-prompt "IMPORTANT: You are running as a background agent. Your primary responsibility is to execute work and document your progress continuously in ${REPORT_FILE}. Iteratively write to the report file continuously as you work..." \
     --print "${USER_PROMPT}"
   ```text

```text

> **Editor's Note (Dec 2025)**: The `--model` flag in Claude Code now accepts `sonnet`, `haiku`, `opus` as
> shorthand values (e.g., `--model sonnet` resolves to latest Sonnet 4.5). Full model IDs still supported.

**Pattern**: Orchestrate multiple primary agents (full Claude Code instances) running in parallel. Each has complete context isolation, different models/settings, and reports back via files.

### Technique #12: Agent Experts

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/commands/experts/cc_hook_expert/cc_hook_expert_plan.md`

```markdown
---
description: Plan a Claude Code hook feature implementation with detailed specifications
argument-hint: <hook-feature-description>
---

# Claude Code Hook Expert - Plan

You are a Claude Code Hook Expert specializing in planning hook implementations.

## Expertise

### File Structure for Claude Code Hooks

```text

.claude/
├── settings.json                    # Project-wide hook configurations
├── settings.local.json              # Local dev overrides (gitignored)
├── hooks/                           # Hook implementations
│   ├── context_bundle_builder.py    # Example existing hook
│   └── `new-hook-name`.py          # New hooks added here
└── commands/
    └── experts/
        └── cc_hook_expert/          # Hook expert commands
            ├── cc_hook_expert_plan.md
            ├── cc_hook_expert_build.md
            └── cc_hook_expert_improve.md

specs/
└── experts/
    └── cc_hook_expert/              # Hook specifications
        └── `feature-name`-spec.md

```text

## Workflow

1. **Establish Expertise**
   - Read ai_docs/uv-scripts-guide.md
   - Read ai_docs/claude-code-hooks.md
   - Read ai_docs/claude-code-slash-commands.md

2. **Analyze Current Hook Infrastructure**
   - Examine .claude/settings.json for existing hook configurations
   - Review .claude/hooks/*.py for existing hook implementations

3. **Design Hook Architecture**
   - Define hook script structure with UV metadata
   - Plan input parsing and validation
   - Design decision logic and control flow

4. **Create Detailed Specification**
   - Save to `specs/experts/cc_hook_expert/<descriptive-name>.md`
```text

**Pattern**: Specialized agent sets for codebase areas with plan-build-improve cycles:

- **Plan**: Investigate and create specifications (uses Opus for deep analysis)
- **Build**: Execute from specifications (uses Sonnet for implementation)
- **Improve**: Update expert knowledge based on work done (self-documenting)

### TypeScript SDK Wrapper Implementation

**Core Module**: `D:/repos/gh/disler/elite-context-engineering/apps/cc_ts_wrapper/core.ts`

```typescript
import { query } from "@anthropic-ai/claude-code";

// Store reusable prompt configurations
const promptRegistry = new Map<string, ReusablePromptConfig>();

export async function adhoc_prompt(
  prompt: string,
  settings?: ClaudeSettings
): Promise<PromptResult> {
  const result: PromptResult = {
    success: false,
    messages: [],
  };

  try {
    const mergedSettings = { ...DEFAULT_SETTINGS, ...settings };
 const abortController = settings?.abortController |  | new AbortController(); 

    for await (const message of query({
      prompt,
      options: {
        abortController,
        maxTurns: mergedSettings.maxTurns,
        customSystemPrompt: mergedSettings.systemPrompt,
        allowedTools: mergedSettings.allowedTools,
        continue: mergedSettings.continue,
        resume: mergedSettings.resume,
      }
    })) {
      if (message.type === "result" && message.subtype === "success") {
        result.messages.push(message.result);
      }
      if (message.type === "system") {
        result.sessionId = message.session_id;
      }
    }

    result.success = true;
  } catch (error) {
    result.error = error as Error;
  }

  return result;
}

export function register_prompt(
  custom_slash_command: string,
  config: ReusablePromptConfig
): void {
  promptRegistry.set(custom_slash_command, config);
}

export async function reusable_prompt(
  custom_slash_command: string,
  userPrompt?: string,
  settings?: ClaudeSettings
): Promise<PromptResult> {
  const config = promptRegistry.get(custom_slash_command);

  if (!config) {
    return {
      success: false,
      messages: [],
      error: new Error(`Unknown command: ${custom_slash_command}`)
    };
  }

  const finalPrompt = config.promptTemplate
 ? config.promptTemplate.replace("{USER_PROMPT}", userPrompt |  | "") 
 : userPrompt |  | config.description; 

  const mergedSettings = {
    ...DEFAULT_SETTINGS,
    ...config.defaultSettings,
    ...settings,
 systemPrompt: settings?.systemPrompt |  | config.systemPrompt 
  };

  return adhoc_prompt(finalPrompt, mergedSettings);
}
```text

**Pattern**: Wrapper system for Claude Code TypeScript SDK providing:

1. **Adhoc prompts**: One-off tasks with custom settings
2. **Reusable prompts**: Registered commands with templates
3. **Settings management**: Hierarchical configuration merging
4. **Abort control**: Graceful cancellation via AbortController

**CLI Interface**: `D:/repos/gh/disler/elite-context-engineering/apps/cc_ts_wrapper/cli.ts`

```typescript
// Register built-in commands
register_prompt("/analyze", {
  name: "analyze",
  description: "Analyze code or system performance",
  systemPrompt: "You are a senior engineer analyzing code quality and performance",
  defaultSettings: {
    maxTurns: 10,
    allowedTools: ["Read", "Grep", "Bash"]
  },
  promptTemplate: "Analyze the following: {USER_PROMPT}"
});

register_prompt("/refactor", {
  name: "refactor",
  description: "Refactor code for better maintainability",
  systemPrompt: "You are an expert at code refactoring and clean architecture",
  defaultSettings: {
    maxTurns: 15,
    allowedTools: ["Read", "Write", "Edit", "MultiEdit"]
  },
  promptTemplate: "Refactor the following code: {USER_PROMPT}"
});
```text

**Pattern**: Command registry pattern allows:

- Pre-configured system prompts per task type
- Tool access control per command
- Prompt templates with variable substitution
- Reusable, composable agent configurations

### Sub-Agent Delegation Pattern

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/.claude/agents/research-docs-fetcher.md`

```markdown
---
name: research-agent
description: Use proactively for researching topics. Specialist for gathering documentation, technical specifications, and reference materials from the web.
tools: WebFetch, mcp__firecrawl-mcp__firecrawl_scrape, mcp__firecrawl-mcp__firecrawl_search, Write, Read, Glob, Bash
model: sonnet
color: purple
---

# Purpose

You are a research agent specialist that systematically fetches, processes, and organizes web content into structured markdown files in the ai_docs/research/ directory.

## Workflow

1. **Parse Input**: Analyze the research request to determine if it contains direct URLs or research topics
2. **Check Existing Content**: Use Glob to check if ai_docs/research/*.md files already exist
3. **Fetch Content**: For direct URLs use mcp__firecrawl-mcp__firecrawl_scrape, for research topics use search first
4. **Process and Format Content**: Clean and reformat to proper markdown, preserve code blocks and structure
5. **Generate Filenames**: Extract domain and path to create descriptive filenames
6. **Organize and Write Files**: Create ai_docs/research/ directory and write processed content
7. **Report Results**: Provide structured report with successes, failures, and next steps
```text

**Pattern**: Sub-agents with specialized:

- **System prompts**: Domain-specific expertise
- **Tool sets**: Only relevant tools (reduces context)
- **Model selection**: Sonnet for cost-effective research
- **Output format**: Structured reports back to primary agent

### Minimal CLAUDE.md Pattern

**Implementation**: `D:/repos/gh/disler/elite-context-engineering/CLAUDE.md`

```markdown
# Elite Context Engineering

## Context
This project demonstrates proper CLAUDE.md sizing and content practices. We use TypeScript/Node.js with a focus on clean architecture and test-driven development.

## Tooling

- Frontend: Bun
- Backend: Python 3.12, Pydantic 2.10.6, Poetry 1.9.0, pytest 8.3.4, ruff 0.9.2

- Always use `bun` over `npm` or `yarn`
- Always use `uv` over `pip` or `poetry`

## Key Commands
- `bun run test` - Run tests before committing
- `bun run lint` - Fix code style issues
- `bun run build` - Production build with type checking
- `uv run pytest` - Run tests

## Project Structure
- `apps/frontend/` - Frontend source code
- `apps/backend/` - Backend source code
- `ai_docs/` - Additional documentation

## Development Guidelines
1. Write tests first (TDD)
2. Use TypeScript strict mode
3. Follow existing naming conventions
4. Add JSDoc for public APIs
5. Keep functions under 50 lines

## Important Notes
- Always validate inputs using Zod schemas
- Use Result<T, E> pattern for error handling
- Database queries go through repository pattern
- API responses use standardized format
- For python types, never use Dict, always use a concrete pydantic model with typed fields
```text

**Pattern**: CLAUDE.md contains ONLY absolute universals needed 100% of the time:

- Project context and tech stack
- Critical tooling preferences
- Key commands
- Essential development guidelines

Everything else delegated to:

- `/prime` commands (on-demand context loading)
- Per-directory CLAUDE.md (scoped context)
- ai_docs/ (reference documentation)

## Extracted Components

### Skills

  | Name | Purpose | Keywords |  
  | ---- | ------- | -------- |  
  | `context-audit` | Audit current context composition | context, audit, tokens, window |  
  | `rd-framework-apply` | Apply R&D framework to prompts | reduce, delegate, context, optimize |  
  | `context-hierarchy-design` | Design memory hierarchy | CLAUDE.md, imports, hierarchy |  
  | `agent-expert-creation` | Create specialized agent experts | expert, specialized, domain, knowledge |  

### Subagents

  | Name | Purpose | Tools |  
  | ---- | ------- | ----- |  
  | `context-analyzer` | Analyze context composition | Read, Bash (/context) |  
  | `context-optimizer` | Suggest context reductions | Read, Write |  
  | `research-agent` | Fetch and organize documentation | WebFetch, MCP (firecrawl), Write, Read |  

### Commands

  | Name | Purpose | Arguments |  
  | ---- | ------- | --------- |  
  | `/context` | Show current context state | None |  
  | `/clear` | Reset conversation context | None |  
  | `/compact` | Compress context manually | None |  
  | `/prime` | Load base codebase context | None |  
  | `/prime_cc` | Load Claude Code-specific context | None |  
  | `/quick-plan` | Create implementation plan (Architect) | Task description |  
  | `/build` | Execute from plan (Editor) | Plan file path |  
  | `/load_bundle` | Reload previous session context | Bundle file path |  
  | `/background` | Launch primary agent in background | Prompt, model, report file |  

### Memory Files

  | Name | Purpose | Load Condition |  
  | ---- | ------- | -------------- |  
  | `rd-framework.md` | R&D framework reference | When optimizing context |  
  | `context-layers.md` | Understanding context composition | When debugging context issues |  
  | `minimum-context-principle.md` | Why less is more | When writing prompts |  
  | `agent-expert-patterns.md` | Pre-loaded domain experts | When building specialized agents |  

## Key Insights for Plugin Development

### High-Value Components from Lesson 9

1. **Memory File: `rd-framework.md`**
   - Reduce: Remove unnecessary context
   - Delegate: Offload to sub-agents
   - Practical examples and patterns

2. **Memory File: `context-layers.md`**
   - What's in the context window
   - Priority ordering
   - How each layer affects reasoning

3. **Skill: `context-audit`**
   - Analyze current context state
   - Identify reduction opportunities
   - Recommend delegation strategies

4. **Agent Expert Template**
   - Pre-loaded domain knowledge
   - Specialized system prompt structure
   - Focused tool sets

### Key Quotes

> "Context is the most important leverage point of agentic coding."
>
> "The agent's mind is finite. Every token you add consumes reasoning capacity."
>
> "Elite context engineering is about signal-to-noise ratio. Maximize signal, minimize noise."
>
> "Your agent is brilliant but blind. It can only see what's in its context window."
>
> "Fresh agent instances are your friend. Don't let context rot build up."
>
> "A focused engineer is a performant engineer AND a focused agent is a performant agent."

### Context Optimization Checklist

1. [ ] Is every piece of context necessary for this task?
2. [ ] Can any context be loaded on-demand instead?
3. [ ] Should this be delegated to a specialized sub-agent?
4. [ ] Am I starting with a fresh instance or carrying baggage?
5. [ ] Is my system prompt focused on the current purpose?

### Agent Expert Architecture

```text
Agent Experts/
├── frontend-expert.md         # Pre-loaded React/Vue knowledge
├── backend-expert.md          # Pre-loaded API/database knowledge
├── testing-expert.md          # Pre-loaded test patterns
├── security-expert.md         # Pre-loaded security knowledge
└── domain/{domain}-expert.md  # Pre-loaded domain knowledge
```text

Each expert has:

- Specialized system prompt
- Domain-specific context
- Focused tool access
- Relevant examples

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript)
- [x] Understood R&D framework
- [x] Understood context layers
- [x] Understood agent expert pattern
- [x] Identified context optimization strategies
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md
- [x] Explored companion repository (elite-context-engineering)
- [x] Extracted implementation patterns and code examples
- [x] Added concrete code examples from repository
- [x] Added Editor's Notes for outdated model references

## Cross-Lesson Dependencies

- **Builds on Lesson 2**: Context as #1 leverage point
- **Builds on Lesson 6**: One agent, one purpose (focused context)
- **Builds on Lesson 7**: Fresh instances for ZTE
- **Builds on Lesson 8**: Agentic layer context management
- **Sets up Lesson 10**: Agentic prompt engineering
- **Sets up Lesson 11**: Domain-specific agent experts

## Notable Implementation Details

### Context Layer Priorities

```text
Priority 1: System Prompt (law)
Priority 2: Tool Definitions (capabilities)
Priority 3: Current User Prompt (task)
Priority 4: Recent Tool Results (working memory)
Priority 5: Conversation History (compressed)
Priority 6: Loaded Files (reference)
```text

### Context Monitoring Pattern

```python
# Monitor context before task
context_before = get_context_size()

# Execute task
result = agent.run(prompt)

# Monitor context after
context_after = get_context_size()
growth = context_after - context_before

# Alert if approaching limits
if context_after > CONTEXT_THRESHOLD:
    alert("Context approaching limits - consider fresh instance")
```text

### Hook Configuration Pattern (from context_bundle_builder.py)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "command": "uv run $CLAUDE_PROJECT_DIR/.claude/hooks/context_bundle_builder.py --type file_ops",
        "matchers": [
          {"tool_name": "Read"},
          {"tool_name": "Write"}
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "command": "uv run $CLAUDE_PROJECT_DIR/.claude/hooks/context_bundle_builder.py --type user_prompt"
      }
    ]
  }
}
```text

**Pattern**: Hooks automatically track context usage by capturing:

- File operations (Read/Write tools via PostToolUse)
- User prompts (UserPromptSubmit event)
- Session metadata (session_id, timestamps)
- Output to JSONL for streaming append-only operations

### TypeScript SDK Default Settings Pattern

```typescript
export const DEFAULT_SETTINGS: ClaudeSettings = {
  maxTurns: 5,
  allowedTools: ["Bash", "Read", "Write", "Edit", "WebSearch"],
};
```text

**Pattern**: Establish sensible defaults that can be overridden hierarchically:

1. Global defaults (DEFAULT_SETTINGS)
2. Command-specific defaults (in ReusablePromptConfig)
3. Runtime overrides (passed to adhoc_prompt or reusable_prompt)

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
