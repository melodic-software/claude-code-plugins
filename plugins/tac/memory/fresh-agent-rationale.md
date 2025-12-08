# Fresh Agent Rationale

Why and when to use fresh agent instances for agentic workflows.

## Three Critical Reasons

### 1. Free Context

**Every token counts.** When you start a fresh agent instance, you get the full context window focused entirely on the task at hand.

| Approach | Available Context | Problem |
| ---------- | ------------------- | --------- |
| Single long session | Depleted by history | Less room for codebase understanding |
| Fresh instance | Full budget | Maximum focus on current task |

For large codebases and complex tasks, this difference is critical. A fresh agent can load more relevant files, consider more context, and produce better results.

### 2. Force Isolation

**Make templates reusable assets.** When you expect to run fresh instances, you naturally create:

- **Isolated prompts**: No dependencies on conversation history
- **Reusable plans**: Work the same way every time
- **Improvable templates**: Can be refined independently

This isolation creates a library of engineering assets that anyone can use:

```text
/chore  --> Always works the same way
/bug    --> No hidden context dependencies
/feature --> Reproducible, predictable results
```markdown

### 3. Prepare for Off-Device

**Enable true AFK agentic coding.** Fresh instances prepare you for:

- Running agents on dedicated machines
- CI/CD pipeline execution
- Overnight batch processing
- Team-shared agent workflows

If your workflow depends on conversational context, it cannot run unattended. Fresh instances with explicit context are the foundation for autonomous execution.

## When to Use Fresh Instances

### Phase Transitions in SDLC

```text
Plan --> Fresh Agent
Code --> Fresh Agent
Test --> Fresh Agent
Review --> Fresh Agent
Document --> Fresh Agent
```markdown

Each phase gets a dedicated agent with full context for that specific task.

### After Completing a Work Unit

When you finish a distinct piece of work:

```text
/chore "update dependencies" --> Agent 1 (planning)
/implement specs/chore.md --> Agent 2 (coding)
```markdown

The implementation agent doesn't need planning artifacts - it just needs the plan.

### When Context is Depleted

Signs your context window is full:

- Agent forgetting earlier conversation
- Responses becoming less coherent
- Missing obvious information
- "Forgetting" files it just read

Start fresh rather than fighting depleted context.

### For Template Execution

Every template invocation should assume fresh context:

```bash
# Each is an independent agent
claude "/chore update deps"
claude "/bug fix login issue"
claude "/feature add dark mode"
```markdown

## The Fresh Instance Pattern

### Pattern: Plan Then Implement

```bash
# Instance 1: Generate plan
claude "/feature add user authentication"
# Output: specs/feature-auth.md

# Instance 2: Execute plan
claude "/implement specs/feature-auth.md"
# Output: Implementation complete
```markdown

Each instance has:

- Full context budget
- Single focused task
- No cross-contamination

### Pattern: Parallel Execution

```bash
# Three independent agents
claude "/chore update frontend deps" &
claude "/chore update backend deps" &
claude "/chore update test deps" &
wait
```markdown

Fresh instances enable parallelization - no shared state to conflict.

## Anti-Patterns

### Stretched Agent Context

**Bad**: One agent doing everything

```text
Agent 1:
- Discuss requirements (fills context)
- Generate plan (more context)
- Implement feature (crowded context)
- Write tests (barely fits)
- Review code (context exhausted)
```yaml

Result: Declining quality as context depletes.

**Good**: Fresh agent per phase

```text
Agent 1: Plan --> plan.md
Agent 2: Implement --> code changes
Agent 3: Test --> test files
Agent 4: Review --> feedback
```yaml

Result: Each phase gets full attention.

### Conversational Dependence

**Bad**: Building up context through conversation

```text
User: Let's add auth
Agent: What kind?
User: OAuth
Agent: Which providers?
User: Google
Agent: What about error handling?
...
```markdown

This creates implicit context that:

- Cannot be reused
- Cannot be shared with team
- Cannot run unattended

**Good**: One-shot with explicit context

```text
User: /feature "Add OAuth authentication with Google provider,
including proper error handling for token refresh failures"
```markdown

All context is explicit and captured in the generated plan.

## Connection to PITER Framework

Fresh instances are essential for the PITER framework (Lesson 4):

| Element | Fresh Instance Role |
| --------- | --------------------- |
| **P** (Prompt Input) | Each issue triggers fresh agent |
| **I** (Issue Classification) | Independent classification per issue |
| **T** (Trigger) | Webhook spawns new instance |
| **E** (Environment) | Clean environment per execution |
| **R** (Review) | Fresh agent for review phase |

Without fresh instances, PITER cannot work - agents would accumulate context from previous issues.

## Practical Guidelines

### Do

- Start fresh for each distinct task
- Capture all context in plans/templates
- Design workflows assuming no conversation history
- Use explicit file references instead of "the file we discussed"

### Avoid

- Multi-phase work in single session
- Relying on "remember when we..."
- Building context through Q&A
- Assuming agent remembers previous runs

## Mental Model

Think of fresh instances like function calls:

```python
# Good: Pure function with explicit inputs
result = plan_feature(description="add auth", context=codebase)

# Bad: Function relying on global state
result = plan_feature()  # Uses hidden conversation state
```markdown

Fresh instances are pure - same input, same output, every time.

## Related Memory Files

- @template-engineering.md - Creating isolated templates
- @meta-prompt-patterns.md - One-shot prompt patterns
- @plan-format-guide.md - Self-contained plan structures
