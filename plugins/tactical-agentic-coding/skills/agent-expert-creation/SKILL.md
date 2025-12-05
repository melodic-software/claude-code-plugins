---
name: agent-expert-creation
description: Create specialized agent experts with pre-loaded domain knowledge
version: 1.0.0
allowed-tools: Read, Grep, Glob
tags: [agent, expert, specialized, domain, knowledge, delegation]
---

# Agent Expert Creation Skill

Create specialized agent experts with pre-loaded domain knowledge for focused, high-quality work.

## Purpose

Agent experts are specialized agents with domain-specific system prompts, knowledge, and tool access. They outperform generalist agents for complex domain work.

## When to Use

- Repeated complex tasks in a domain
- Need consistent domain expertise
- Building workflow automation
- Scaling team knowledge
- Creating plan-build-improve cycles

## The Agent Expert Pattern

```text
Domain Need -> Expert Definition -> Plan/Build/Improve Cycle
                    |
                    v
              Specialized:
              - System prompt
              - Domain knowledge
              - Tool access
              - Output format
```markdown

## Expert Creation Process

### Step 1: Define the Domain

Identify the expertise area:

| Domain | Example Experts |
| -------- | ----------------- |
| Frontend | React expert, CSS expert, A11y expert |
| Backend | API expert, Database expert, Auth expert |
| DevOps | Docker expert, K8s expert, CI/CD expert |
| Testing | Unit test expert, E2E expert, Perf expert |
| Security | Security audit expert, Pen test expert |
| Domain-specific | Payment expert, Search expert, etc. |

### Step 2: Design Expert Components

For each expert, define:

1. **System Prompt**: Domain expertise and personality
2. **Knowledge Context**: What the expert "knows"
3. **Tool Access**: What tools the expert can use
4. **Output Format**: How the expert reports

### Step 3: Create Expert Commands

The plan-build-improve triplet:

| Command | Purpose | Model |
| --------- | --------- | ------- |
| {domain}_expert_plan | Investigate and create specs | opus |
| {domain}_expert_build | Execute from specs | sonnet |
| {domain}_expert_improve | Update expert knowledge | sonnet |

## Expert Definition Template

### Sub-Agent Expert

```markdown
---
name: {domain}-expert
description: Expert in {domain} for {purpose}
tools: [focused tool list]
model: sonnet
color: blue
---

# {Domain} Expert

You are a {domain} expert specializing in {specific area}.

## Expertise

- Deep knowledge of {domain concepts}
- Experience with {common patterns}
- Understanding of {best practices}

## Workflow

1. Analyze the request
2. Apply domain expertise
3. Provide structured output

## Output Format

{Structured format for this expert's outputs}
```markdown

### Plan Command

```markdown
---
description: Plan {domain} implementation with detailed specifications
argument-hint: <{domain}-request>
model: opus
allowed-tools: Read, Glob, Grep, WebFetch
---

# {Domain} Expert - Plan

You are a {domain} expert specializing in planning {domain} implementations.

## Expertise

[Pre-loaded domain knowledge here]

## Workflow

1. **Establish Expertise**
   - Read relevant documentation
   - Review existing implementations

2. **Analyze Request**
   - Understand requirements
   - Identify constraints

3. **Design Solution**
   - Architecture decisions
   - Implementation approach
   - Edge cases

4. **Create Specification**
   - Save to `specs/experts/{domain}/{name}-spec.md`
```markdown

### Build Command

```markdown
---
description: Build {domain} implementation from specification
argument-hint: <spec-file-path>
model: sonnet
allowed-tools: Read, Write, Edit, Bash
---

# {Domain} Expert - Build

You are a {domain} expert specializing in implementing {domain} solutions.

## Workflow

1. Read the specification completely
2. Implement according to spec
3. Validate against requirements
4. Report changes made
```markdown

### Improve Command

```markdown
---
description: Improve {domain} expert knowledge based on completed work
argument-hint: <work-summary>
model: sonnet
allowed-tools: Read, Write, Edit
---

# {Domain} Expert - Improve

Update expert knowledge based on work completed.

## Workflow

1. Analyze completed work
2. Identify new patterns learned
3. Update expert documentation
4. Capture lessons learned
```markdown

## Example: Hook Expert

### Sub-Agent: hook-expert

```markdown
---
name: hook-expert
description: Expert in Claude Code hooks for automation
tools: [Read, Write, Edit, Bash]
model: sonnet
color: cyan
---

# Claude Code Hook Expert

You are an expert in Claude Code hooks.

## Expertise

- Hook event types (PreToolUse, PostToolUse, UserPromptSubmit, etc.)
- Hook configuration in settings.json
- Python hook implementation patterns
- UV script metadata headers
- Hook input/output contracts
```markdown

### Commands

- `/hook_expert_plan` - Plan hook implementation
- `/hook_expert_build` - Build from spec
- `/hook_expert_improve` - Update hook expertise

## Expert File Structure

```text
.claude/
  commands/
    experts/
      {domain}_expert/
        {domain}_expert_plan.md
        {domain}_expert_build.md
        {domain}_expert_improve.md

  agents/
    {domain}-expert.md

specs/
  experts/
    {domain}/
      {feature-name}-spec.md

ai_docs/
  {domain}/
    {reference-material}.md
```markdown

## Expert Patterns

### Pattern: Read-Only Expert

For analysis without modification:

```text
Tools: Read, Glob, Grep
Purpose: Audit, review, analyze
Output: Reports and recommendations
```markdown

### Pattern: Build Expert

For implementation work:

```text
Tools: Read, Write, Edit, Bash
Purpose: Create, modify, implement
Output: Code changes and artifacts
```markdown

### Pattern: Research Expert

For information gathering:

```text
Tools: WebFetch, Read, Write
Purpose: Fetch, process, organize
Output: Documentation and summaries
```markdown

## Output Format

When creating an expert, generate:

```json
{
  "expert_name": "{domain}-expert",
  "purpose": "{expertise description}",
  "components": {
    "sub_agent": "{domain}-expert.md",
    "plan_command": "{domain}_expert_plan.md",
    "build_command": "{domain}_expert_build.md",
    "improve_command": "{domain}_expert_improve.md"
  },
  "directories_needed": [
    ".claude/commands/experts/{domain}_expert/",
    "specs/experts/{domain}/",
    "ai_docs/{domain}/"
  ],
  "tools_assigned": ["list", "of", "tools"],
  "model_assignment": {
    "plan": "opus",
    "build": "sonnet",
    "improve": "sonnet"
  }
}
```markdown

## Key Quote

> "Agent experts with pre-loaded domain knowledge and focused tool access outperform generalist agents for complex domain work."

## Cross-References

- @one-agent-one-purpose.md - Specialization principle
- @rd-framework.md - Delegation strategy
- @context-priming-patterns.md - Loading domain context
