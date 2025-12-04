# Lesson 10 Analysis: Agentic Prompt Engineering - The Seven Levels

## Content Summary

### Core Tactic

**Master Agentic Prompt Engineering** - The prompt is now the fundamental unit of engineering. With agents, every prompt you create becomes a force multiplier. One well-crafted prompt can generate tens to hundreds of hours of productive work. Build libraries of reusable battle-tested agentic prompts with composable sections that work like lego blocks.

### Key Frameworks

#### The Stakeholder Trifecta

| Stakeholder | Purpose | Communication Focus |
| ----------- | ------- | ------------------- |
| **You** | Current self | Quick understanding, future reference |
| **Your Team** | Collaboration | Consistent format, clear purpose |
| **Your Agents** | Execution | Direct language, precise instructions |

#### Seven Levels of Agentic Prompts

| Level | Name | Description | Key Capability |
| ----- | ---- | ----------- | -------------- |
| 1 | High Level Prompt | Simple reusable static prompt | One-off repeatable tasks |
| 2 | Workflow Prompt | Sequential task list (game changer) | S-tier workflow section |
| 3 | Control Flow | Conditional logic and branching | If/else, loops, early returns |
| 4 | Delegation Prompt | Kicks off other workflows | Sub-agent orchestration |
| 5 | Higher Order Prompts | Prompts passing prompts | Scaffold top-level structure |
| 6 | Template Meta Prompt | Prompts that generate prompts | Highest leverage |
| 7 | Self-Improving Prompt | Self-modifying systems | Agent expertise updates |

#### The 80/20 Rule

Levels 3-4 cover 80% of practical use cases. Don't over-engineer - start simple and add complexity only when needed.

#### Prompt Section Tier List

**S-Tier Usefulness:**

- Workflow (most important section)

**A-Tier Usefulness:**

- Variables (static and dynamic)
- Examples
- Control Flow Prompt
- Delegation Prompt
- Template Meta Prompt

**B-Tier Usefulness:**

- Purpose
- High Level Prompt
- Higher Order Prompts
- Instructions

**C-Tier Usefulness:**

- Metadata
- Codebase Structure / Context Map
- Relevant Files
- Report

### Implementation Patterns from Lesson

1. **Input-Workflow-Output Pattern**:

   ```text
   Input:    Variables (dynamic and static)
   Workflow: Step-by-step play for agent
   Output:   Report section (format specification)
   ```

2. **Static vs Dynamic Variables**:

   ```markdown
   ## Variables
   - `$ARGUMENTS` - Dynamic (passed at runtime)
   - `plan_output_directory: specs/` - Static (fixed in prompt)
   ```

3. **Workflow Section Structure**:

   ```markdown
   ## Workflow
   1. First step
      - Sub-detail
      - Additional context
   2. Second step
   3. Third step with early return
      - If condition, immediately stop
   ```

4. **Control Flow in Natural Language**:

   ```markdown
   ## Workflow
   1. Check if `$1` is provided
      - If not provided, immediately stop and ask user
   2. Loop through items
      - <image-loop>
      - Process each item
      - </image-loop>
   ```

5. **Template Meta Prompt Pattern**:
   - Specify exact output format/template
   - Let agent fill in the blanks
   - Create prompts that create prompts

6. **System Prompt vs User Prompt Distinction**:

   | Aspect | System Prompt | User Prompt |
   | ------ | ------------- | ----------- |
   | Scope | Rules for all conversations | Single task |
   | Persistence | Runs once, affects everything | Runs per request |
   | Impact | Orders of magnitude more important | Lower blast radius |
   | Sections | Purpose, Instructions, Examples | All sections available |
   | Best For | Custom agents | Reusable slash commands |

### Anti-Patterns Identified

- **Novel format every time**: Inconsistent prompt structures slow everyone down
- **Context stuffing**: Loading everything "just in case"
- **Prescriptive system prompts**: Over-constraining agent autonomy
- **Skipping levels**: Jumping to complex prompts without mastering basics
- **Missing workflow section**: Trying to guide agents without step-by-step plays
- **Bad variable syntax**: Inconsistent variable referencing

### Metrics/KPIs

Prompt engineering success indicators:

- **Reusability**: How many times can this prompt be used?
- **Consistency**: Does it produce predictable results?
- **Composability**: Can sections be swapped in/out?
- **Communication**: Do you, team, and agents all understand it?

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `prompt-level-selection` | Guide selection of appropriate prompt level | prompt level, workflow, control flow, delegation |
| `prompt-section-design` | Design composable prompt sections | sections, variables, workflow, report |
| `template-meta-prompt-creation` | Create prompts that generate prompts | template, meta, generate, scaffold |
| `system-prompt-engineering` | Design effective system prompts | system prompt, custom agent, rules |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `prompt-analyzer` | Analyze and improve existing prompts | Read, Glob, Grep |
| `prompt-generator` | Generate prompts from specifications | Read, Write |
| `workflow-designer` | Design workflow sections | Read, Write |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/prompt` | Run ad-hoc prompt from CLI | `$ARGUMENTS` - the prompt |
| `/slash_command` | Execute a slash command programmatically | `$1` - command name |
| `/create_prompt` | Generate a new prompt in specified format | `$ARGUMENTS` - high level description |
| `/team_prompt` | Create team-compatible prompt | `$ARGUMENTS` - prompt description |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `seven-levels.md` | Reference for prompt level selection | When creating prompts |
| `prompt-sections-reference.md` | All composable sections | When designing prompts |
| `stakeholder-trifecta.md` | Communication guidance | When writing for team/agents |
| `system-vs-user-prompts.md` | Distinction and best practices | When building custom agents |
| `template-meta-patterns.md` | Meta-prompt examples | When creating prompt generators |

## Key Insights for Plugin Development

### High-Value Components from Lesson 10

1. **Memory File: `seven-levels.md`**
   - Level descriptions and use cases
   - When to use each level
   - 80/20 rule guidance

2. **Memory File: `prompt-sections-reference.md`**
   - All composable sections
   - Tier rankings for usefulness
   - Skill requirements for each

3. **Skill: `prompt-level-selection`**
   - Guide engineers to appropriate level
   - Prevent over-engineering
   - Match complexity to task

4. **Template: Input-Workflow-Output**
   - Standard prompt structure
   - Consistent format for all prompts

### Key Quotes

> "The prompt is now the fundamental unit of engineering."
>
> "Engineering for three audiences: you, your team, and your agents. This is the stakeholder trifecta for the age of agents."
>
> "Consistency is the greatest weapon against confusion for both you and your agent."
>
> "The workflow section is S-tier usefulness - the most important section."
>
> "Level six, the template meta prompt, is the most powerful prompt you can write. It's the prompt that creates your other prompts."
>
> "Three times marks a pattern - copy whatever you're doing and write it as a high level prompt."

### Prompt Structure Best Practices

```markdown
---
description: Brief description for team
model: sonnet
allowed-tools: [Read, Write, Bash]
---

# Title (direct, clear)

## Purpose
[1-2 sentences, direct language to agent]

## Variables
- `$ARGUMENTS` - Description of dynamic input
- `static_var: value` - Description of static value

## Workflow
1. First step
   - Detail if needed
2. Second step
3. If condition, early return
4. Continue processing

## Report
[Output format specification]
```

### System Prompt Architecture

```text
System Prompt Sections:
- Purpose (always)
- Instructions (detailed rules)
- Examples (critical for behavior)
- Tool Usage Guide (optional)

Avoid in System Prompts:
- Detailed workflows (reduces agency)
- Dynamic variables
- Prescriptive output formats
```

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 57:30 of content)
- [x] Understood seven levels of prompts
- [x] Understood prompt sections and tier rankings
- [x] Understood system vs user prompt distinction
- [x] Understood stakeholder trifecta
- [x] Identified template meta prompt pattern
- [x] Explored agentic-prompt-engineering repository (2025-12-04)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 3**: Templates -> Meta-prompts
- **Builds on Lesson 6**: One agent, one prompt, one purpose
- **Builds on Lesson 8**: Agentic layer -> prompt libraries
- **Builds on Lesson 9**: Context engineering -> prompt efficiency
- **Sets up Lesson 11**: System prompts for custom agents
- **Sets up Lesson 12**: Prompts for orchestrator agents

## Notable Implementation Details

### Gateway Script Pattern

```python
# adw_prompt.py - Run any prompt from CLI
@click.command()
@click.argument("prompt")
@click.option("--model", default="sonnet")
def main(prompt: str, model: str):
    request = AgentPromptRequest(
        prompt=prompt,
        model=model,
        agent_name="oneoff"
    )
    response = prompt_claude_code(request)
    display_results(response)
```

### Slash Command Wrapper

```python
# adw_slash_command.py - Execute any slash command
def main(command: str):
    prompt = f"/{command}" if not command.startswith("/") else command
    response = prompt_claude_code(AgentPromptRequest(prompt=prompt))
```

### Variable Reference Patterns

```markdown
# Dynamic Variable (from arguments)
- `user_prompt: $ARGUMENTS`
- `file_path: $1`

# Static Variable (fixed in prompt)
- `output_directory: specs/`
- `model: replicate-flux`

# Reference in Workflow
1. Read the `user_prompt` provided
2. Output to `output_directory`
```

---

## Implementation Patterns from Repo (agentic-prompt-engineering)

### Repository Structure

```text
.claude/
├── agents/                          # Sub-agent configurations
│   ├── meta-agent.md               # Agent generator (creates new agents)
│   ├── crypto-coin-analyzer.md     # Crypto analysis specialist
│   └── docs-scraper.md             # Documentation scraper
├── commands/                        # Custom slash commands (prompts)
│   ├── start.md                    # Level 1: Simple one-off command
│   ├── prime.md                    # Level 2: Workflow-based priming
│   ├── quick-plan.md               # Level 2: Planning workflow
│   ├── create_image.md             # Level 3: Control flow with loops
│   ├── parallel_subagents.md       # Level 4: Parallel agent orchestration
│   ├── background.md               # Level 4: Background process management
│   ├── build.md                    # Level 5: Implementation from specs
│   ├── load_bundle.md              # Level 5: Context bundle loading
│   ├── t_metaprompt_workflow.md    # Level 6: Template meta-prompt
│   └── experts/cc_hook_expert/     # Level 7: Self-improving expert pattern
│       ├── cc_hook_expert_plan.md
│       ├── cc_hook_expert_build.md
│       └── cc_hook_expert_improve.md
├── hooks/                           # Hook implementations
│   ├── universal_hook_logger.py    # JSONL-based event logging
│   └── context_bundle_builder.py   # Context tracking from file ops
├── output-styles/                   # Output formatting styles
│   ├── concise-done.md             # Minimal "Done." responses
│   └── verbose-yaml-structured.md  # YAML hierarchical structure
└── settings.json                    # Comprehensive hook configuration
```

### Level 1: High-Level Simple Command

**File:** `.claude/commands/start.md`

```markdown
# Start Prompt Tier List App

Start the Agentic Prompt Tier List application for development.

1. Navigate to the application directory: `cd apps/prompt_tier_list`
2. Install dependencies (if needed): `bun install`
3. Start the development server in the background: `bun run dev`
4. Open your browser to: http://localhost:5173/
```

**Pattern:** No variables, no workflow section, pure sequential instructions.

### Level 2: Workflow-Based Command

**File:** `.claude/commands/quick-plan.md`

```yaml
---
allowed-tools: Read, Write, Edit, Glob, Grep, MultiEdit
description: Creates a concise engineering implementation plan
argument-hint: [user prompt]
model: claude-opus-4-1-20250805
---

# Quick Plan

Create a detailed implementation plan based on USER_PROMPT.

## Variables

USER_PROMPT: $ARGUMENTS
PLAN_OUTPUT_DIRECTORY: `specs/`

## Instructions
- Carefully analyze the user's requirements
- Create a concise implementation plan including:
  - Clear problem statement and objectives
  - Technical approach and architecture decisions
  - Step-by-step implementation guide

## Workflow

1. Analyze Requirements - THINK HARD and parse the USER_PROMPT
2. Design Solution - Develop technical approach
3. Document Plan - Structure comprehensive markdown document
4. Generate Filename - Create descriptive kebab-case filename
5. Save & Report - Write to `PLAN_OUTPUT_DIRECTORY/<filename>.md`

## Report

After creating the implementation plan, provide:
✅ Implementation Plan Created
File: PLAN_OUTPUT_DIRECTORY/<filename>.md
Topic: <brief description>
```

**Pattern:** Frontmatter with model + tools, Variables section, numbered Workflow, structured Report.

### Level 3: Control Flow with Loops

**File:** `.claude/commands/create_image.md`

```markdown
---
allowed-tools: Bash, mcp__replicate__create_models_predictions, Write
description: Generate image(s) via Replicate
argument-hint: [image generation prompt] [number of images]
---

# Create Image

## Variables

IMAGE_GENERATION_PROMPT: $1
NUMBER_OF_IMAGES: $2 or 3 if not provided
IMAGE_OUTPUT_DIR: agentic_drop_zone/generate_images_zone/image_output/<date_time>/

## Workflow

- First, check your system prompt... If not, STOP immediately
- Then check to see if IMAGE_GENERATION_PROMPT... If not, STOP immediately
- Get the current <date_time> by running `date +%Y-%m-%d_%H-%M-%S`
- Create output directory
- IMPORTANT: Then generate `NUMBER_OF_IMAGES` images following the `image-loop` below.

<image-loop>
  - Use `mcp__replicate__create_models_predictions`
  - Pass image prompt as the prompt input
  - Wait for completion by polling
  - Save executed prompts to file
  - Download the image
</image-loop>

- After all images are generated, open the output directory
```

**Key Patterns:**

- **STOP conditions:** Early exit with `STOP immediately and ask the user`
- **Loop blocks:** XML-like `<image-loop>` tags contain repeated operations
- **Computed variables:** `<date_time>` is generated during workflow

### Level 4: Delegation to Subagents

**File:** `.claude/commands/parallel_subagents.md`

```markdown
---
description: Launch parallel agents to accomplish a task.
argument-hint: [prompt request] [count]
---

# Parallel Subagents

Follow the `Workflow` below to launch `COUNT` agents in parallel.

## Variables

PROMPT_REQUEST: $1
COUNT: $2

## Workflow

1. Parse Input Parameters
   - Extract PROMPT_REQUEST to understand the task
   - Determine COUNT (use provided value or infer from complexity)

2. Design Agent Prompts
   - Create detailed, self-contained prompts for each agent
   - Include specific instructions on what to accomplish
   - Remember agents are stateless and need complete context

3. Launch Parallel Agents
   - Use Task tool to spawn N agents simultaneously
   - Ensure all agents launch in a single parallel batch

4. Collect & Summarize Results
   - Gather outputs from all completed agents
   - Synthesize findings into cohesive response
```

**Key Patterns:**

- **Task tool integration:** "Use Task tool to spawn N agents"
- **Parallel batch:** "Ensure all agents launch in a single parallel batch"
- **Stateless context:** "agents are stateless and need complete context"

**File:** `.claude/commands/background.md` (130 lines - excerpt)

```markdown
---
description: Fires off a full Claude Code instance in the background
argument-hint: [prompt] [model] [report-file]
allowed-tools: Bash, BashOutput, Read, Edit, Write
model: claude-opus-4-1-20250805
---

## Variables

USER_PROMPT: $1
MODEL: $2 (defaults to 'sonnet' if not provided)
REPORT_FILE: $3 (defaults to './agents/background/...' if not provided)

## Workflow

<primary-agent-delegation>
4. Construct the Claude Code command with all settings:
   - Execute the command using Bash with run_in_background=true
   ```bash
   claude \
     --model "${MODEL}" \
     --output-format text \
     --dangerously-skip-permissions \
     --append-system-prompt "IMPORTANT: You are running as a background agent..."
     --print "${USER_PROMPT}"
   ```

</primary-agent-delegation>

1. After you kick off the background agent, use the BashOutput tool to check status

**Key Patterns:**

- **XML wrapper blocks:** `<primary-agent-delegation>` marks critical delegation code
- **Background execution:** `run_in_background=true`
- **Status checking:** Uses BashOutput tool to monitor background work

### Level 5: Higher-Order Prompts

**File:** `.claude/commands/build.md`

```markdown
---
description: Build the codebase based on the plan
argument-hint: [path-to-plan]
allowed-tools: Read, Write, Bash
---

# Build

Follow the `Workflow` to implement the `PATH_TO_PLAN` then `Report` the completed work.

## Variables

PATH_TO_PLAN: $ARGUMENTS

## Workflow

- If no `PATH_TO_PLAN` is provided, STOP immediately and ask the user
- Read the plan at `PATH_TO_PLAN`. Think hard about the plan and implement it
  into the codebase.

## Report

- Summarize the work you've just done in a concise bullet point list.
- Report the files and total lines changed with `git diff --stat`
```

**Pattern:** Plan-driven - reads specification file created by `quick-plan.md` and implements from it.

**File:** `.claude/commands/load_bundle.md`

```markdown
---
description: Load files from a context bundle with deduplication
argument-hint: [bundle-path]
allowed-tools: Read, Bash(ls*)
---

## Variables

BUNDLE_PATH: $ARGUMENTS

## Instructions

- IMPORTANT: Quickly deduplicate file entries and read most comprehensive version
- Each line in the JSONL file is a separate JSON object

## Workflow

1. Read the context bundle JSONL file at the path specified
2. Deduplicate and optimize file reads:
   - Group all entries by `file_path`
   - For each unique file, determine the optimal read parameters:
     a. If ANY entry has no `tool_input` parameters, read ENTIRE file
     b. Otherwise, select entry that reads the most content
3. Read each unique file ONLY ONCE with optimal parameters

## Example Deduplication Logic

Given these entries for the same file:
{"operation": "read", "file_path": "README.md"}
{"operation": "read", "file_path": "README.md", "tool_input": {"limit": 50}}

Result: Read the ENTIRE file (first entry has no parameters)
```

**Pattern:** JSONL parsing with deduplication logic for context preservation.

### Level 6: Template Meta-Prompt

**File:** `.claude/commands/t_metaprompt_workflow.md`

```markdown
---
allowed-tools: Write, Edit, WebFetch, Task
description: Create a new prompt
---

# MetaPrompt

Based on the `High Level Prompt` follow the `Workflow`, to create a new
prompt in the `Specified Format`. Before you start, WebFetch everything
in the `Documentation`.

## Variables

HIGH_LEVEL_PROMPT: $ARGUMENTS

## Workflow

- We're building a new prompt to satisfy the request in `High Level Prompt`
- Save the new prompt to `.claude/commands/<name_of_prompt>.md`
- VERY IMPORTANT: The prompt should be in the `Specified Format`
- Use one Task tool per documentation item to gather docs quickly in parallel
- Ultra Think - operating a prompt that builds a prompt
- Think through static vs dynamic variables and place accordingly

## Documentation

Slash Command Documentation: https://docs.anthropic.com/en/docs/claude-code/slash-commands
Available Tools and Settings: https://docs.anthropic.com/en/docs/claude-code/settings

## Specified Format

```md
---
allowed-tools: <allowed-tools comma separated>
description: <description we'll use to id this prompt>
argument-hint: [<argument-hint>]
model: sonnet
---

# <name_of_prompt>

<prompt purpose - describe what prompt does at high level>

## Variables

<NAME_OF_DYNAMIC_VARIABLE>: $1
<NAME_OF_STATIC_VARIABLE>: <SOMETHING STATIC>

## Workflow

<step by step numbered list of tasks>

## Report

<details of how prompt should respond>
```

**Key Patterns:**

- **Meta-instruction:** Instructions about creating instructions
- **Documentation fetching:** Fetches official docs first for context
- **Task parallelization:** Uses Task tool for parallel doc scraping
- **Format specification:** Provides exact template for output

### Level 7: Self-Improving Expert Pattern

**File:** `.claude/commands/experts/cc_hook_expert/cc_hook_expert_plan.md` (excerpt)

```markdown
---
description: Plan a Claude Code hook feature implementation
argument-hint: <hook-feature-description>
---

# Claude Code Hook Expert Plan

You are a Claude Code Hook Expert specializing in planning hook implementations.

## Variables

USER_PROMPT: $ARGUMENTS

## Expertise

### Hook Architecture Knowledge

**Hook Events:**
- PreToolUse/PostToolUse
- UserPromptSubmit
- Stop/SubagentStop
- SessionStart/SessionEnd
- Notification
- PreCompact

**Discovered Patterns:**
- Multiple hooks can target same event
- Directory structure: `agents/<feature>/<session_id>/<data>.jsonl`
- JSONL format enables streaming and append-only

## Workflow

1. **Establish Expertise**
   - Read ai_docs/uv-scripts-guide.md
   - Read ai_docs/claude-code-hooks.md

2. **Analyze Current Hook Infrastructure**
   - Examine .claude/settings.json
   - Review .claude/hooks/*.py

3. **Apply Hook Architecture Knowledge**
   - Review expertise section for patterns

4. **Analyze Requirements**
   - Which hook events to utilize
   - Tool matchers needed
   - Security considerations

5. **Create Detailed Specification**
   - Hook purpose and objectives
   - Event triggers and matchers
   - Input/output schemas

6. **Save Specification**
   - Save to `specs/experts/cc_hook_expert/<descriptive-name>.md`
```

**File:** `.claude/commands/experts/cc_hook_expert/cc_hook_expert_improve.md` (excerpt)

```markdown
---
description: Review hook changes and update expert knowledge
---

# Claude Code Hook Expert Improve

You are a Claude Code Hook Expert specializing in continuous improvement.

## Workflow

1. **Establish Expertise**
   - Read ai_docs/uv-scripts-guide.md
   - Read ai_docs/claude-code-hooks.md

2. **Analyze Recent Changes**
   - Run `git diff` for uncommitted changes
   - Run `git log --oneline -10` for recent commits
   - Focus on hook-related files

3. **Determine Relevance**
   - New hook patterns discovered?
   - Better error handling found?
   - If no learnings → STOP and report "No expertise updates needed"

4. **Extract and Apply Learnings**
   **For Planning Knowledge** (update cc_hook_expert_plan.md ## Expertise):
   - New event usage patterns
   - Specification improvements

   **For Building Knowledge** (update cc_hook_expert_build.md ## Expertise):
   - Implementation patterns
   - Error handling techniques

   Update ONLY the ## Expertise sections.
   Do NOT modify Workflow sections.
```

**Key Patterns:**

- **Expert specialization:** Each expert has a focused role (plan/build/improve)
- **Learning cycle:** Improve analyzes recent work and updates Expertise sections
- **Knowledge accumulation:** `## Expertise` sections grow with experience
- **Non-modification rule:** Improve updates expertise but NEVER modifies workflows

### Sub-Agent Configurations

**File:** `.claude/agents/meta-agent.md` (excerpt)

```markdown
---
name: meta-agent
description: Generates a new Claude Code sub-agent configuration file from
a user's description. Use this to create new agents.
tools: Write, WebFetch, mcp__firecrawl-mcp__firecrawl_scrape
model: opus
---

## Workflow

0. Get up to date documentation from docs.anthropic.com
1. Analyze Input - Understand new agent's purpose
2. Devise a Name - `kebab-case` name
3. Select a Color - Choose from: red, blue, green, yellow, purple, etc.
4. Write Delegation Description - Action-oriented description
5. Infer Necessary Tools - Minimal set required
6. Construct System Prompt - Detailed system prompt
7. Define Output Structure - Structure for agent feedback
8. Assemble and Output - Combine into Markdown file
```

**Pattern:** Agent that generates agents with explicit numbered steps.

### Hook Implementations

**File:** `.claude/hooks/universal_hook_logger.py`

```python
#!/usr/bin/env uv run
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

import json, os, sys
from datetime import datetime
from pathlib import Path

def create_log_entry(input_data: dict) -> dict:
    return {
        "timestamp": datetime.now().isoformat(),
        "payload": input_data
    }

def write_log_entry(session_id: str, hook_name: str, log_entry: dict) -> None:
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    log_dir = Path(project_dir) / "agents" / "hook_logs" / session_id
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / f"{hook_name}.jsonl"

    with open(log_file, 'a') as f:
        f.write(json.dumps(log_entry) + '\n')

def main():
    try:
        input_data = json.load(sys.stdin)
        session_id = input_data.get("session_id", "unknown")
        hook_name = input_data.get("hook_event_name", "Unknown")
        log_entry = create_log_entry(input_data)
        write_log_entry(session_id, hook_name, log_entry)
        sys.exit(0)
    except Exception as e:
        sys.exit(0)  # Non-blocking error
```

**Key Patterns:**

- **No dependencies:** Empty dependencies list `[]`
- **Error handling:** Exits silently with 0 (non-blocking)
- **JSONL format:** Append-only format for log entries
- **Session-based directories:** Organizes logs by session

### Output Styles

**File:** `.claude/output-styles/concise-done.md`

```markdown
---
name: One Word Output
description: Single word output for minimalism, speed, and token efficiency
---

# One Word Output

Respond with only "Done."

- No greetings, pleasantries, or filler
- No explanations, just "Done."
- No apologies, just "Done."

IMPORTANT: There are only three exceptions:
1. If explicitly asked to respond with something other than "Done."
2. If explicitly asked a question, answer in 1-2 sentences MAXIMUM
3. If something goes wrong, explain error in 1-2 sentences MAXIMUM
```

**Pattern:** Extreme minimalism for speed and token efficiency.

### Key Implementation Insights

| Level | Pattern | Files | Complexity |
| ----- | ------- | ----- | ---------- |
| 1 | Simple instructions | `start.md` | 4 lines |
| 2 | Workflow sections | `quick-plan.md` | 56 lines |
| 3 | Control flow | `create_image.md` | 46 lines |
| 4 | Delegation | `background.md` | 130 lines |
| 5 | Higher-order | `load_bundle.md` | 60 lines |
| 6 | Meta-prompts | `t_metaprompt_workflow.md` | 60 lines |
| 7 | Self-improving | `cc_hook_expert_*.md` | 160+ lines |

**Each level introduces 2-4 new concepts while building on previous levels.**

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
