# Lesson 4 Analysis: AFK Agents - Let Your Product Build Itself

## Content Summary

### Core Tactic

**Stay Out The Loop** - Move beyond "human in the loop" agentic coding to "out of loop" autonomous systems. Using the PITER Framework, build AFK (Away From Keyboard) agents that run while you're not there, letting your product build itself.

### Key Frameworks

#### PITER Framework (Four Elements of AFK Agents)

| Element | Purpose | Implementation |
| ------- | ------- | -------------- |
| **P - Prompt Input** | Source of work requests | GitHub Issues (title + body = prompt) |
| **I - (Implicit)** | Issue classification | Classify as chore/bug/feature |
| **T - Trigger** | What kicks off the workflow | GitHub Webhooks, Cron jobs, Manual CLI |
| **E - Environment** | Where agents run | Dedicated device/sandbox with full control |
| **R - Review** | Human oversight point | GitHub Pull Requests |

#### AI Developer Workflows (ADWs)

An ADW is:

- A **reusable agentic workflow** that combines:
  - Deterministic code (Python/TypeScript scripts)
  - Non-deterministic agents (Claude Code prompts)
  - Triggers and orchestration logic
- The **highest composition level** of agentic coding
- The synthesis of previous generation deterministic code with new generation LLMs

#### Two Types of Agentic Coding

| Type | Description | Human Role |
| ---- | ----------- | ---------- |
| **In-Loop** | Prompting back and forth at your device | Active participant |
| **Out-of-Loop** | Off-device, agents run autonomously | Define work, review results |

### Implementation Patterns from Repo (tac-4)

1. **ADW Plan-Build Workflow** (`adw_plan_build.py`):

   ```python
   # Workflow steps:
   # 1. Fetch GitHub issue details
   # 2. Create feature branch: feature/issue-{number}-{slug}
   # 3. Plan Agent: Generate implementation plan
   # 4. Build Agent: Implement the solution
   # 5. Create PR with full context
   ```

2. **Issue Classification** (`/classify_issue`):

   ```markdown
   # Github Issue Command Selection
   - Respond with `/chore` if the issue is a chore.
   - Respond with `/bug` if the issue is a bug.
   - Respond with `/feature` if the issue is a feature.
   - Respond with `0` if the issue isn't any of the above.
   ```

3. **Micro Agents Pattern** - Multiple specialized agents:
   - `issue_classifier` - Classify issue type
   - `branch_generator` - Create git branch names
   - `sdlc_planner` - Generate implementation plans
   - `sdlc_implementor` - Implement the solution
   - `pr_creator` - Create pull requests
   - `*_committer` - Commit changes

4. **Trigger Options**:
   - `trigger_cron.py` - Polls GitHub every 20 seconds
   - `trigger_webhook.py` - Real-time GitHub webhook events
   - Manual CLI: `uv run adw_plan_build.py <issue-number>`

5. **ADW ID Tracking** - Every workflow gets unique 8-char ID:

   ```text
   a1b2c3d4_ops: Starting ADW workflow
   a1b2c3d4_sdlc_planner: Building implementation plan
   a1b2c3d4_sdlc_implementor: Implementing solution
   ```

6. **Claude Code Programmable Mode**:

   ```python
   def execute_template(request: AgentTemplateRequest) -> AgentPromptResponse:
       # Build prompt with slash command + args
       # Run: claude -p <prompt> --model <model> --dangerously-skip-permissions
       # Stream output to JSONL for logging
   ```

7. **Hooks for Observability**:
   - `pre_tool_use.py` - Intercept before tool execution
   - `post_tool_use.py` - Log after tool execution
   - `stop.py` - Handle agent completion
   - `notification.py` - Send notifications

### Anti-Patterns Identified

- **In-loop prompting** for repetitive tasks that could be automated
- **Ad hoc prompts** that can't be improved or version controlled
- **Single agent** trying to handle entire SDLC
- **Missing observability** - not knowing what agents are doing
- **Generic cloud tools** that don't understand your codebase

### Metrics/KPIs

Connects back to Lesson 2 KPIs:

- **Presence: DOWN** - Stay out the loop
- **Size: UP** - Automate entire features
- **Streak: UP** - ADWs produce consistent results
- **Attempts: DOWN** - Templated workflows reduce iterations

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `adw-design` | Guide creation of AI Developer Workflows | ADW, workflow, automation, PITER |
| `piter-setup` | Set up PITER framework elements | PITER, prompt input, trigger, environment, review |
| `issue-classification` | Configure issue classification for ADWs | classify, chore, bug, feature |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| `sdlc-planner` | Generate implementation plans from issues | Read, Write, Glob, Grep |
| `sdlc-implementer` | Implement plans with validation | Read, Write, Edit, Bash |
| `issue-classifier` | Classify issues into problem classes | Read |
| `branch-generator` | Generate semantic branch names | Read, Bash |
| `pr-creator` | Create well-formatted pull requests | Read, Bash |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/classify_issue` | Classify GitHub issue type | `$ARGUMENTS` - issue JSON |
| `/generate_branch_name` | Generate branch name | `$1` type, `$2` adw_id, `$3` issue JSON |
| `/commit` | Create formatted commit | `$1` agent, `$2` type, `$3` issue JSON |
| `/pull_request` | Create PR with context | `$1` branch, `$2` issue, `$3` plan, `$4` adw_id |
| `/find_plan_file` | Find generated plan file | `$ARGUMENTS` - agent output |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `piter-framework.md` | PITER framework reference | When setting up AFK agents |
| `adw-anatomy.md` | ADW structure and patterns | When building workflows |
| `outloop-checklist.md` | Checklist for outloop systems | Before deploying ADWs |
| `agentic-layer.md` | Agentic layer architecture | When designing agent systems |

## Key Insights for Plugin Development

### High-Value Components from Lesson 4

1. **Skill: `adw-design`**
   - Guide users through ADW creation
   - PITER framework validation
   - Best practices for micro agents

2. **Memory File: `piter-framework.md`**
   - Complete PITER reference
   - Implementation options for each element
   - Trigger configurations (webhook, cron, manual)

3. **Memory File: `adw-anatomy.md`**
   - ADW structure patterns
   - Agent composition patterns
   - Observability requirements

4. **Command Templates for ADW Support**
   - `/classify_issue` - Issue classification
   - `/generate_branch_name` - Branch naming
   - `/pull_request` - PR creation

### ADW Structure Pattern

```text
adws/
  adw_plan_build.py      # Main orchestrator
  agent.py               # Claude Code integration
  data_types.py          # Pydantic models
  github.py              # GitHub API operations
  trigger_cron.py        # Cron-based trigger
  trigger_webhook.py     # Webhook-based trigger
  health_check.py        # Environment validation
  README.md              # Documentation
```markdown

### Key Architectural Decisions

1. **Separation of Concerns**
   - Each agent has one job
   - Deterministic code handles orchestration
   - Non-deterministic agents handle intelligence

2. **Observability First**
   - ADW ID tracking throughout
   - Issue comments for live updates
   - JSONL logs for debugging

3. **Environment Isolation**
   - Dedicated environment for AFK agents
   - Prevents interference with development
   - Enables `--dangerously-skip-permissions`

### Key Quotes

> "Stay out the loop and focus on building the system that builds the system."
>
> "Your agentic pipeline is too valuable to outsource to a third party tool."
>
> "Most engineers are sitting at their device, prompting back and forth, wasting time on problems their agents could solve."
>
> "If you are not wrong now, you will be. It's only a matter of time. Remember, tools will change and models will improve."
>
> "The ADW is the synthesis of previous generation deterministic code and new generation non-deterministic language models."

### Programmable Claude Code Example

```python
# From agent.py - executing Claude Code programmatically
result = subprocess.run(
    [
        claude_code_path,
        "-p", prompt,
        "--output-format", "stream-json",
        "--dangerously-skip-permissions",
        "--model", model,
        "--verbose"
    ],
    capture_output=True,
    text=True
)
```markdown

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 46:27!)
- [x] Explored tac-4 repository structure
- [x] Read adws/adw_plan_build.py (main ADW orchestrator)
- [x] Read adws/README.md (comprehensive documentation)
- [x] Read .claude/commands/classify_issue.md
- [x] Identified hooks pattern (.claude/hooks/)
- [x] Understood trigger patterns (cron, webhook, manual)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 1**: Programmable Claude Code from shell/Python
- **Builds on Lesson 2**: Solving problem classes, not individual problems
- **Builds on Lesson 3**: Templates chained into ADWs
- **Sets up Lesson 5**: Closing the loops with validation
- **Sets up Lesson 6**: Specialized micro agents
- **Sets up Lesson 7**: ZTE (Zero Touch Engineering) goal

## Notable Implementation Details

### GitHub Integration Pattern

```python
# Issue comments for live progress
def make_issue_comment(issue_number: str, message: str):
    """Post progress updates to GitHub issue."""
    subprocess.run(["gh", "issue", "comment", issue_number, "--body", message])

# Branch naming convention
# {type}-{issue_number}-{adw_id}-{slug}
# Example: feat-456-e5f6g7h8-add-user-authentication
```markdown

### Health Check Pattern

```python
# Validate environment before running ADW
def health_check():
    """Verify all PITER elements are configured."""
    # 1. Check environment variables
    # 2. Verify GitHub auth
    # 3. Test Claude Code CLI
    # 4. Validate repository access
    # 5. Post health status to issue
```yaml

### Model Selection Strategy

- **Classifier**: Sonnet (fast, simple decision)
- **Planner**: Opus (complex reasoning for comprehensive plans)
- **Implementer**: Opus (complex implementation work)
- **Branch Generator**: Sonnet (simple string generation)
- **PR Creator**: Sonnet (formatting, not reasoning)

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
