# ADW Anatomy

AI Developer Workflows (ADWs) are the highest composition level of agentic coding - reusable workflows that combine deterministic code with non-deterministic agents.

## What is an ADW?

An ADW is the synthesis of:

- **Deterministic code**: Python/TypeScript scripts for orchestration
- **Non-deterministic agents**: Claude Code prompts for intelligence
- **Triggers**: Webhooks, cron, or manual invocation
- **Observability**: Logging, comments, tracking

```text
ADW = Orchestrator + Micro Agents + Triggers + Observability
```markdown

## ADW Directory Structure

```text
adws/
├── main_workflow.py       # Main orchestrator
├── agent.py               # Claude Code integration
├── data_types.py          # Type definitions (Pydantic)
├── github.py              # External service integration
├── trigger_cron.py        # Cron-based trigger
├── trigger_webhook.py     # Webhook-based trigger
├── health_check.py        # Environment validation
├── utils.py               # Shared utilities
└── README.md              # Documentation
```markdown

## Core Components

### 1. Orchestrator (`main_workflow.py`)

The orchestrator coordinates the entire workflow:

```python
# Pseudocode - actual implementation in Python/TypeScript
def run_adw(issue_number: str, adw_id: str):
    # 1. Fetch issue context
    issue = fetch_github_issue(issue_number)

    # 2. Classify issue type
    issue_type = execute_agent("classifier", issue)

    # 3. Create branch
    branch_name = execute_agent("branch_generator", issue)
    create_branch(branch_name)

    # 4. Plan phase
    plan = execute_agent("planner", issue_type, issue)
    commit("planner", plan)

    # 5. Build phase
    execute_agent("implementer", plan)
    commit("implementer", "implementation")

    # 6. Create PR
    create_pull_request(branch_name, issue, plan)
```markdown

### 2. Micro Agents

Specialized agents with single responsibilities:

| Agent | Responsibility | Model |
| ------- | --------------- | ------- |
| `issue_classifier` | Classify issue type | Haiku (fast) |
| `branch_generator` | Create branch name | Haiku (fast) |
| `sdlc_planner` | Generate implementation plan | Sonnet/Opus (reasoning) |
| `sdlc_implementer` | Implement the solution | Sonnet/Opus (coding) |
| `committer` | Create semantic commits | Haiku (fast) |
| `pr_creator` | Create pull request | Haiku (fast) |

### 3. Agent Executor (`agent.py`)

Handles Claude Code CLI integration:

```python
def execute_template(request):
    """Execute a slash command via Claude Code CLI."""
    prompt = f"/{request.command} {request.args}"

    result = subprocess.run([
        "claude",
        "-p", prompt,
        "--model", request.model,
        "--output-format", "stream-json",
        "--dangerously-skip-permissions"
    ], capture_output=True, text=True)

    return parse_result(result)
```markdown

### 4. External Service Integration (`github.py`)

Handles GitHub operations:

- Fetch issue details
- Post issue comments (progress updates)
- Create pull requests
- Manage branches

## ADW ID Tracking

Every workflow run gets a unique 8-character UUID:

```text
a1b2c3d4_ops: Starting ADW workflow
a1b2c3d4_classifier: Classifying issue as /feature
a1b2c3d4_planner: Generating implementation plan
a1b2c3d4_implementer: Implementing solution
a1b2c3d4_pr_creator: Creating pull request
```yaml

Benefits:

- Correlate logs across agents
- Track issue comments to specific run
- Debug failed workflows
- Enable parallel ADW execution

## Workflow Phases

### Phase 1: Context Gathering

```text
Input: Issue number
Actions:
  - Fetch issue from GitHub
  - Extract title, body, labels
  - Post "Starting ADW" comment
Output: Issue context object
```markdown

### Phase 2: Classification

```text
Input: Issue context
Actions:
  - Execute /classify_issue command
  - Parse result (chore/bug/feature)
  - Post classification comment
Output: Issue type
```markdown

### Phase 3: Branch Creation

```text
Input: Issue type, issue context
Actions:
  - Execute /generate_branch_name
  - Create and checkout branch
Output: Branch name
```markdown

### Phase 4: Planning

```text
Input: Issue type, issue context
Actions:
  - Execute /chore, /bug, or /feature
  - Write plan to specs/*.md
  - Commit with "planner:" prefix
  - Post plan summary as comment
Output: Plan file path
```markdown

### Phase 5: Implementation

```text
Input: Plan file path
Actions:
  - Execute /implement with plan
  - Make code changes
  - Commit with "implementer:" prefix
  - Post implementation summary
Output: Code changes
```markdown

### Phase 6: PR Creation

```text
Input: Branch, issue, plan
Actions:
  - Push branch to remote
  - Create PR with context
  - Link PR in issue comments
Output: PR URL
```markdown

## Model Selection Strategy

Match model to task complexity:

| Task | Model | Rationale |
| ------ | ------- | ----------- |
| Classification | Haiku | Simple decision, speed matters |
| Branch naming | Haiku | String generation, no reasoning |
| Plan generation | Sonnet/Opus | Complex reasoning needed |
| Implementation | Sonnet/Opus | Complex coding needed |
| Commit messages | Haiku | Formatting, not reasoning |
| PR creation | Haiku | Template filling |

## Observability Patterns

### Issue Comments

```text
[adw_id] Starting ADW workflow for issue #123
[adw_id] Classified as: /feature
[adw_id] Created branch: feature-123-a1b2c3d4-add-auth
[adw_id] Plan generated: specs/feature-add-auth.md
[adw_id] Implementation complete: 5 files changed
[adw_id] PR created: #456
```markdown

### Logging Structure

```text
agents/
└── {adw_id}/
    ├── classifier/
    │   ├── prompts/
    │   └── raw_output.jsonl
    ├── planner/
    │   ├── prompts/
    │   └── raw_output.jsonl
    └── implementer/
        ├── prompts/
        └── raw_output.jsonl
```markdown

## Anti-Patterns

### Single Monolithic Agent

**Bad**: One agent doing classify + plan + implement + commit + PR

**Good**: Micro agents with single responsibilities

### Missing Observability

**Bad**: No logging, no issue comments, no tracking

**Good**: ADW ID tracking, issue comments, structured logs

### Generic Cloud Tools

**Bad**: Using generic cloud coding tools that don't know your codebase

**Good**: Custom ADW that understands your domain and conventions

### Ad-Hoc Prompts

**Bad**: One-off prompts that can't be improved

**Good**: Version-controlled templates that get better over time

## Related Memory Files

- @piter-framework.md - The four elements of AFK agents
- @outloop-checklist.md - Deployment readiness
- @fresh-agent-rationale.md - Why micro agents matter
