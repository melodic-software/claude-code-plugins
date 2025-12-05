# Agent Lifecycle: CRUD Operations

Create, Read, Update, Delete - managing agents at scale.

## The Lifecycle Pattern

```text
Create --> Command --> Monitor --> Aggregate --> Delete
   | | | | |
   v          v           v            v           v
Template   Prompt      Status      Results     Cleanup
```markdown

## CRUD Operations

### Create

Spin up a new specialized agent.

```python
create_agent(
    name="scout_1",
    template="scout-fast",  # Pre-defined configuration
    # OR
    system_prompt="...",     # Custom prompt
    model="haiku",
    allowed_tools=["Read", "Glob", "Grep"]
)
```markdown

**Best Practices**:

- Use templates for consistency
- Give descriptive names
- Select appropriate model
- Minimize tool access

### Command

Send prompts to an agent.

```python
command_agent(
    agent_id="scout_1",
    prompt="""
    Analyze the authentication module in src/auth/.
    Focus on:
    1. Current implementation patterns
    2. Security considerations
    3. Potential improvements

    Report findings in structured format.
    """
)
```markdown

**Best Practices**:

- Detailed, specific prompts
- Clear expected output format
- Include all relevant context
- One task per command

### Monitor (Read)

Check agent status and progress.

```python
# Check status
check_agent_status(
    agent_id="scout_1",
    verbose_logs=True
)

# List all agents
list_agents()

# Read agent logs
read_agent_logs(
    agent_id="scout_1",
    offset=0,
    limit=50
)
```markdown

**Status Values**:

- `idle` - Ready for commands
- `executing` - Processing prompt
- `waiting` - Waiting for input
- `blocked` - Permission needed
- `complete` - Finished

### Delete

Clean up agents when work is complete.

```python
delete_agent(agent_id="scout_1")
```markdown

**Key Principle**:
> "You must treat your agents as deletable temporary resources that serve a single purpose."

## Lifecycle Patterns

### Scout-Build Pattern

```text
1. Create scout agent
2. Command: Analyze codebase
3. Monitor until complete
4. Aggregate scout findings
5. Delete scout

6. Create builder agent
7. Command: Implement based on findings
8. Monitor until complete
9. Aggregate build results
10. Delete builder
```markdown

### Scout-Build-Review Pattern

```text
Phase 1: Scout
- Create scouts (parallel)
- Command each with specific area
- Aggregate findings

Phase 2: Build
- Create builder
- Command with scout reports
- Monitor implementation

Phase 3: Review
- Create reviewer
- Command to verify implementation
- Generate final report

Cleanup: Delete all agents
```markdown

### Parallel Execution

```text
Create: scout_1, scout_2, scout_3 (parallel)
Command each with different area
Monitor all until complete
Aggregate all findings
Delete all scouts

Create: builder_1, builder_2 (parallel)
Command each with different files
Monitor all until complete
Aggregate all changes
Delete all builders
```markdown

## Agent Templates

### Fast Scout Template

```yaml
---
name: scout-fast
description: Quick codebase reconnaissance
tools: [Read, Glob, Grep]
model: haiku
---

# Scout Agent

Analyze codebase efficiently. Focus on:
- File structure
- Key patterns
- Relevant code sections

Report findings concisely.
```markdown

### Builder Template

```yaml
---
name: builder
description: Code implementation specialist
tools: [Read, Write, Edit, Bash]
model: sonnet
---

# Builder Agent

Implement changes based on specifications.
Follow existing patterns.
Test your changes.
Report what was modified.
```markdown

### Reviewer Template

```yaml
---
name: reviewer
description: Code review and verification
tools: [Read, Grep, Glob, Bash]
model: sonnet
---

# Reviewer Agent

Verify implementation against requirements.
Check for issues and risks.
Report findings by severity.
```markdown

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
| -------------- | --------- | ---------- |
| Keeping dead agents | Resource waste, context pollution | Delete when done |
| Long-lived agents | Context accumulation | Fresh agents per task |
| Generic agents | Unfocused work | Specialized templates |
| Missing cleanup | Dead agents accumulate | Always delete |
| Reusing agents | Context contamination | Create fresh |

## Key Quotes

> "The rate at which you create and command your agents becomes the constraint of your engineering output."

> "Treat agents as deletable temporary resources."

> "One agent, one prompt, one purpose - then delete."

## Implementation Note

> **SDK Constraint**: Full lifecycle management requires Claude Agent SDK with custom MCP tools. This pattern is for backend services, not Claude Code subagents.

Within Claude Code, use the Task tool for delegating work, understanding that subagents cannot spawn other subagents.

## Cross-References

- @three-pillars-orchestration.md - Full framework
- @single-interface-pattern.md - Orchestrator architecture
- @agent-lifecycle-management skill - Implementation guidance
- @one-agent-one-purpose.md - Agent specialization principle
