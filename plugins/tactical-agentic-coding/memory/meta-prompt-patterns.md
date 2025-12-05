# Meta-Prompt Patterns

Understanding the prompt hierarchy and composition patterns for scalable agentic workflows.

## The Prompt Hierarchy

| Level | Type | Description | Example |
| ------- | ------ | ------------- | --------- |
| 1 | **High-Level Prompt** | Simple description void of detail | "Add dark mode support" |
| 2 | **Meta-Prompt** | Prompt that builds a prompt (template) | `/feature` command |
| 3 | **Plan** | Generated detailed specification | `specs/add-dark-mode.md` |
| 4 | **Higher-Order Prompt (HOP)** | Prompt that accepts another prompt as input | `/implement` command |

## Flow: From Idea to Implementation

```text
1. You write:     "Add dark mode support"
                        |
                        v
2. Meta-prompt:   /feature generates detailed plan
                        |
                        v
3. Plan created:  specs/feature-dark-mode.md (comprehensive spec)
                        |
                        v
4. HOP executes:  /implement specs/feature-dark-mode.md
                        |
                        v
5. Work done:     Agent implements the plan
```markdown

## Pattern 1: Simple Meta-Prompt

One input, one output - the basic building block:

```markdown
# Template: /chore

Input:  "Update all dependencies to latest versions"
Output: specs/chore-update-dependencies.md

The meta-prompt:
- Takes your one-line description
- Activates reasoning mode
- Generates comprehensive plan
- Writes to specs directory
```markdown

## Pattern 2: Higher-Order Prompt (HOP)

A HOP accepts another prompt (usually a plan) as input:

```markdown
# /implement command

Input:  Path to a plan file (another prompt)
Action: Read plan, reason about it, execute it

## Instructions
- Read the plan
- THINK HARD about the implementation approach
- Execute the step-by-step tasks
- Run validation commands
- Report results with git diff --stat

## Plan
$ARGUMENTS
```markdown

Key insight: Plans are prompts. When you pass a plan to `/implement`, you're passing a prompt to a prompt.

## Pattern 3: Composable Commands

Commands can call other commands for composition:

```markdown
# /install command (composable)

## Read and Execute
.claude/commands/prime.md

## Run
Install FE and BE dependencies
Run ./scripts/copy_dot_env.sh

## Report
Output the work in concise bullet points
```markdown

This `/install` command:

1. First runs `/prime` (by reading its file)
2. Then installs dependencies
3. Then reports what was done

## Activating Reasoning Mode

The "think hard" instruction activates Claude Code's extended thinking:

```markdown
## Instructions

Use your reasoning model: THINK HARD about the plan and
the steps to accomplish this work.
```markdown

Reasoning keywords (in order of intensity):

- "think" - basic reasoning
- "think hard" - deeper analysis
- "think harder" - extended reasoning
- "ultrathink" - maximum thinking budget

Use "think hard" in meta-prompts because plan generation benefits from deeper reasoning.

## When to Use Each Pattern

| Situation | Pattern | Example |
| ----------- | --------- | --------- |
| Generate a plan from description | Simple Meta-Prompt | `/chore "update deps"` |
| Execute a generated plan | HOP | `/implement specs/plan.md` |
| Combine multiple operations | Composable | `/install` calling `/prime` |
| Complex multi-step workflow | Chained | `/feature` -> review -> `/implement` |

## Example: Complete Workflow

```bash
# 1. Generate plan with meta-prompt
claude "/feature add user authentication with OAuth"

# 2. Review the generated plan (human in loop)
cat specs/feature-oauth-auth.md

# 3. Execute plan with HOP
claude "/implement specs/feature-oauth-auth.md"
```yaml

Each step uses a fresh agent instance:

- Plan generation: focused on planning
- Plan review: human verification
- Implementation: focused on coding

## Anti-Patterns

### Conversational Planning

**Bad**: Multi-turn conversation to build a plan

```text
User: I want to add auth
Agent: What kind of auth?
User: OAuth
Agent: Which providers?
User: Google and GitHub
...
```markdown

**Good**: One-shot meta-prompt

```text
User: /feature "Add OAuth authentication with Google and GitHub providers"
Agent: *generates complete plan in one shot*
```markdown

### Stretched Context

**Bad**: One agent doing plan + implement + test + review

The agent's context fills with planning artifacts, leaving less room for implementation quality.

**Good**: Fresh agent for each phase

Each agent has full context budget for its specific task.

## Related Memory Files

- @template-engineering.md - Template anatomy and design
- @plan-format-guide.md - Standard plan structures
- @fresh-agent-rationale.md - Why fresh instances matter
