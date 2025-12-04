# Lesson 8 Analysis: The Agentic Layer - The Meta-Tactic

## Content Summary

### Core Tactic

**Prioritize Agentics** - More than half of your engineering time should be spent on the agentic layer rather than the application layer. This tactic represents all others compressed into one. The agentic layer is the combination of deterministic code and non-deterministic agents that operates on your codebase.

### Key Frameworks

#### The Two Layers

| Layer | Contents | Time Investment |
| --- | --- | --- |
| **Agentic Layer** | ADWs, prompts, plans, templates, hooks | 50%+ of your time |
| **Application Layer** | DevOps, infrastructure, database, application code | <50% of your time |

#### The Guiding Question

> "Am I working on the agentic layer or am I working on the application layer?"

This single question compresses all tactics, KPIs, and leverage points into one daily decision framework.

#### Minimum Viable Agentic Layer

```bash
specs/                          # Plans for agents to follow
├── *.md                        # Implementation specifications

.claude/commands/               # Agentic prompts
├── prime.md                    # Context priming
├── chore.md                    # Chore planning template
├── implement.md                # Implementation HOP
└── *.md                        # Other slash commands

adws/                           # AI Developer Workflows
├── adw_modules/
│   └── agent.py                # Core agent execution
└── adw_*.py                    # Top-level workflow scripts
```

#### Scaled Agentic Layer

```bash
specs/                          # Plans and specifications
├── issue-*.md                  # Issue-based specs
└── deep_specs/                 # Complex architectural specs

.claude/                        # Agent configuration
├── commands/                   # Agentic prompts
├── hooks/                      # Event-driven automation
└── settings.json               # Agent configuration

adws/                           # AI Developer Workflows
├── adw_modules/                # Core logic modules
├── adw_triggers/               # Workflow triggers
├── adw_tests/                  # Testing suite
├── adw_data/                   # Agent database
├── adw_*_iso.py                # Isolated workflows
└── adw_sdlc_*.py               # Full SDLC workflows

agents/                         # Agent output & observability
├── {adw_id}/                   # Per-workflow outputs

trees/                          # Agent worktrees (isolation)
└── {branch_name}/              # Isolated work environments
```

### Implementation Patterns from Repo (tac-8)

The lesson showcases five distinct codebase examples:

1. **Agentic Layer Primitives** (`tac8_app1__agent_layer_primitives`):
   - Minimum viable agentic layer structure
   - Gateway scripts: `adw_prompt.py`, `adw_slash_command.py`
   - Composed workflow: `adw_chore_implement.py`

2. **Multi-Agent ToDone** (`tac8_app2__multi_agent_todone`):
   - Task-based multi-agent system with Git worktrees
   - Shared `tasks.markdown` file for task management
   - Cron trigger picks up tasks every 5 seconds
   - Tags: `#opus` (model), `#adw_plan_implement_update_task` (workflow)

3. **Out-Loop Multi-Agent Task Board** (`tac8_app3__out_loop_multi_agent_task_board`):
   - Data science/Jupyter notebook scenario
   - Parallel experiment execution across worktrees

4. **Agentic Prototyping** (`tac8_app4__agentic_prototyping`):
   - Notion database as prompt input source
   - Board view with status columns
   - Prototype generation from high-level prompts
   - Template meta-prompts for MCP server generation

5. **NLQ to SQL with Embedded Agents** (`tac8_app5__nlq_to_sql_aea`):
   - Agents embedded inside the application
   - Chat interface with named agents (Nexus, Roon)
   - Multiple simultaneous agent sessions

### The Secret Revealed: Composable Primitives

The "secret" of TAC is reiterated: **It's not about the SDLC at all. It's about composable agentic primitives.**

Primitives include:

- Prompts (individual slash commands)
- Template meta-prompts (generate plans)
- Higher-Order Prompts (accept other prompts)
- ADW scripts (orchestrate agents)
- Triggers (kick off workflows)
- State management (persist across steps)

### Gateway Script Pattern

The simplest entry point to agentic coding:

```python
#!/usr/bin/env -S uv run --script
from agent import prompt_claude_code, AgentPromptRequest

def main(prompt: str, model: str):
    """Run an adhoc Claude Code prompt from the command line."""
    request = AgentPromptRequest(
        prompt=prompt,
        model=model,
        agent_name="oneoff"
    )
    response = prompt_claude_code(request)
    # Process and display response
```

### Anti-Patterns Identified

- **Staying in application layer**: Spending more time on app code than agentic layer
- **Competing with templated agents**: Trying to outperform well-designed ADWs manually
- **Tool fixation**: Focusing on Claude Code instead of primitives/concepts
- **Rejecting future beliefs**: Not believing agents can run your codebase
- **Stale mindset**: Running away from or standing still against the future

### Metrics/KPIs

The lesson ties all KPIs together:

- **50%+ time on agentic layer** (new meta-metric)
- **Attempts: DOWN** - Templates reduce iterations
- **Size: UP** - Agents handle larger work
- **Streak: UP** - Consistent success
- **Presence: DOWN** - Target zero

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| --- | --- | --- |
| `agentic-layer-audit` | Audit codebase for agentic layer coverage | agentic layer, primitives, audit |
| `minimum-viable-agentic` | Guide creation of minimum viable agentic layer | MVP, minimum, agentic layer, start |
| `task-based-multiagent` | Set up task-based multi-agent systems | task, multi-agent, worktree, parallel |
| `notion-integration` | Configure Notion as prompt input source | notion, trigger, prompt input |

### Subagents

| Name | Purpose | Tools |
| --- | --- | --- |
| `gateway-script-runner` | Execute ad-hoc prompts | Read, Write, Bash |
| `task-executor` | Execute tasks from task file | Read, Write, Bash, Glob |
| `prototype-generator` | Generate full prototypes from prompts | Read, Write, Bash, Edit |

### Commands

| Name | Purpose | Arguments |
| --- | --- | --- |
| `/prime` | Prime agent with codebase context | None |
| `/start` | Start application services | None |
| `/chore` | Generate chore plan | `$ARGUMENTS` - chore description |
| `/feature` | Generate feature plan | `$ARGUMENTS` - feature description |
| `/implement` | Execute a plan | `$ARGUMENTS` - plan file path |

### Memory Files

| Name | Purpose | Load Condition |
| --- | --- | --- |
| `agentic-layer-structure.md` | Reference for layer organization | When setting up agentic layer |
| `primitives-reference.md` | Complete primitives catalog | When composing workflows |
| `gateway-script-patterns.md` | Entry point script patterns | When starting agentic coding |
| `the-guiding-question.md` | Daily decision framework | Always (meta-tactic) |

## Key Insights for Plugin Development

### High-Value Components from Lesson 8

1. **Memory File: `agentic-layer-structure.md`**
   - Minimum viable vs scaled structures
   - Directory organization patterns
   - What belongs in each directory

2. **Memory File: `the-guiding-question.md`**
   - Daily decision framework
   - Agentic layer vs application layer
   - Time allocation guidance

3. **Skill: `agentic-layer-audit`**
   - Evaluate current agentic layer coverage
   - Identify gaps and opportunities
   - Prioritize next investments

4. **Gateway Scripts Collection**
   - `adw_prompt.py` - Ad-hoc prompts
   - `adw_slash_command.py` - Slash command execution
   - `adw_chore_implement.py` - Composed workflow

### All 8 Tactics Summary

| # | Tactic | Core Idea |
| --- | --- | --- |
| 1 | **Stop Coding** | Agents write code now |
| 2 | **Adopt Agent's Perspective** | 12 leverage points |
| 3 | **Template Your Engineering** | Meta-prompts and plans |
| 4 | **Stay Out The Loop** | PITER framework, AFK agents |
| 5 | **Always Add Feedback Loops** | Tests, validation, self-correction |
| 6 | **One Agent, One Purpose** | Specialized focused agents |
| 7 | **Target Zero-Touch Engineering** | Drop presence to 1, auto-ship |
| 8 | **Prioritize Agentics** | 50%+ time on agentic layer |

### Key Quotes

> "On a day-to-day tactical level, even if you forget all eight tactics, this is all you need to think about. Am I working on the agentic layer or am I working on the application layer?"
>
> "The agentic layer is the combination of traditional deterministic code that is stored in your ADW's directory as a scriptable layer that combines deterministic code with the new non-deterministic agentic technology."
>
> "An engineer that is scaling up their codebase with fleets of agents that solve problem classes completely outperforms an engineer using classical AI coding."
>
> "What we're seeing here is the commoditization of implementation and early signs of the commoditization of engineering."
>
> "The irreplaceable engineer of the future is not writing a single line of code."
>
> "When the agents arrived, something changed. We weren't just AI coding anymore. We started orchestrating intelligence."

### Agentic Engineering Manifesto

The lesson positions TAC as more than a course:

- A **manifesto** for the next phase of software engineering
- A **guideline/framework/codex** for agentic engineering
- The groundwork for a new role: **Agentic Engineer**

### The Value Shift

Engineering value is moving up the stack:

- System design and architecture
- Encoding domain expertise for agents
- Quality control and validation
- Review systems
- **Creative problem decomposition** (encoded in ADWs)

### Task File Pattern (Multi-Agent)

```markdown
# Tasks

## To Do

- [ ] 🔴 Add edge cases to tweet CSV #opus
- [ ] 🔵 Create filtered dataset (positive only)
- [ ] 🟢 Build augmented training model #adw_plan_implement_update_task

## In Progress

- [🌞 a1b2c3d4] Processing edge cases...

## Done

- [✅ e5f6g7h8] Created filtered dataset
```

Tags modify behavior:

- `#opus` - Use Opus model
- `#adw_plan_implement_update_task` - Different workflow

### Notion Integration Pattern

```python
# Trigger: Poll Notion every 15 seconds
def get_notion_tasks():
    # Fetch tasks from Notion database
    # Filter by status (Not Started, In Progress)
    # Return task objects

def process_task(task):
    # Create worktree
    # Execute appropriate ADW
    # Update Notion status
    # Post results to task
```

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 1:03:31 of content!)
- [x] Explored tac-8 repository structure (5 sub-applications)
- [x] Read app1 README (minimum viable agentic layer)
- [x] Read adw_prompt.py (gateway script)
- [x] Understood multi-agent task system pattern
- [x] Understood notion integration pattern
- [x] Understood embedded agent pattern
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Culminates Lesson 1**: Stop coding -> agents operate codebase
- **Culminates Lesson 2**: 12 leverage points -> build agentic layer
- **Culminates Lesson 3**: Templates -> encoded in agentic layer
- **Culminates Lesson 4**: PITER/ADWs -> core of agentic layer
- **Culminates Lesson 5**: Testing -> feedback loops in layer
- **Culminates Lesson 6**: Specialized agents -> primitives
- **Culminates Lesson 7**: ZTE -> target state of agentic layer
- **Sets up PAC**: Principled Agentic Coding (mentioned as extension)

## Notable Implementation Details

### Gateway Script Architecture

```python
# adw_prompt.py - Simplest possible agentic script
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
    # Prefix with slash if needed
    prompt = f"/{command}" if not command.startswith("/") else command
    # Execute via Claude Code
    response = prompt_claude_code(AgentPromptRequest(prompt=prompt))
```

### Composed Workflow Pattern

```python
# adw_chore_implement.py
def main(chore_description: str):
    # Step 1: Run chore template (generate plan)
    chore_response = run_agent("/chore", chore_description)
    plan_path = extract_plan_path(chore_response)

    # Step 2: Run implement HOP (execute plan)
    implement_response = run_agent("/implement", plan_path)

    # Return combined results
```

### Multiple App Patterns in tac-8

| App | Pattern | Key Innovation |
| --- | ------- | -------------- |
| app1 | Primitives | Minimum viable structure |
| app2 | Task-based multi-agent | Shared task file, worktrees |
| app3 | Out-loop task board | Data science workflows |
| app4 | Agentic prototyping | Notion as prompt source |
| app5 | Embedded agents | Agents inside application |

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
