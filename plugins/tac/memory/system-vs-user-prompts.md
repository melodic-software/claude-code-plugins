# System Prompts vs User Prompts

Understanding the distinction between system prompts and user prompts is critical for effective agent design.

## The Distinction

| Aspect | System Prompt | User Prompt |
| -------- | --------------- | ------------- |
| **Scope** | Rules for all conversations | Single task |
| **Persistence** | Runs once, affects everything | Runs per request |
| **Impact** | Orders of magnitude more important | Lower blast radius |
| **Best For** | Custom agents | Reusable slash commands |
| **Sections** | Purpose, Instructions, Examples | All sections available |

## System Prompt Characteristics

### When to Use

- Building custom agents with specialized behavior
- Establishing persistent rules and constraints
- Defining agent personality and expertise
- Setting tool usage patterns

### Architecture

```markdown
---
name: domain-expert
description: Expert for automatic delegation
tools: [focused tool list]
model: sonnet
---

# Agent Title

## Purpose
You are a [role definition] specializing in [domain].

## Instructions
- Rule 1: Always do X
- Rule 2: Never do Y
- Rule 3: When Z happens, respond with A

## Examples
### Example 1: Good Response
Input: "..."
Output: "..."

### Example 2: Edge Case
Input: "..."
Output: "..."
```markdown

### What to Include

- **Purpose**: What the agent is and does
- **Instructions**: Rules, constraints, boundaries
- **Examples**: Critical for shaping behavior
- **Tool Usage Guide**: When optional, how to use tools

### What to Avoid

| Avoid | Why |
| ------- | ----- |
| Detailed workflows | Reduces agent autonomy |
| Dynamic variables | System prompt is static |
| Prescriptive output formats | Over-constrains responses |
| Everything "just in case" | Context bloat |

## User Prompt Characteristics

### When to Use

- Creating reusable slash commands
- Building task-specific workflows
- Handling dynamic inputs
- Short-lived, focused tasks

### Architecture

```markdown
---
description: Task description
argument-hint: [args]
allowed-tools: Read, Write, Edit
model: sonnet
---

# Task Title

## Variables
USER_INPUT: $ARGUMENTS
OUTPUT_DIR: specs/

## Workflow
1. Validate input
2. Process task
3. Generate output

## Report
[Output format]
```markdown

### What to Include

- **Variables**: Dynamic inputs from user
- **Workflow**: Step-by-step execution plan
- **Report**: Output format specification
- **Control Flow**: Conditionals, loops, delegation

### What to Avoid

| Avoid | Why |
| ------- | ----- |
| Defining agent personality | That's system prompt's job |
| Establishing global rules | Won't persist |
| Over-constraining | User prompts are flexible |

## Interaction Pattern

```text
System Prompt (persistent)
|
+-- Defines: Who the agent is
|   - Personality
|   - Expertise
|   - Rules
|   - Boundaries
|
v
User Prompt (per-request)
|
+-- Defines: What to do now
    - Specific task
    - Inputs
    - Workflow
    - Output format
```markdown

## When to Use Each

| Scenario | Use |
| ---------- | ----- |
| Building a specialized agent | System Prompt |
| Creating reusable task | User Prompt (slash command) |
| Establishing boundaries | System Prompt |
| Handling dynamic inputs | User Prompt |
| Shaping behavior with examples | System Prompt |
| Sequential workflow execution | User Prompt |
| Setting tool restrictions | Either (frontmatter) |

## System Prompt Design Guidelines

### 1. Focus on Identity

```markdown
## Purpose
You are a security expert specializing in code review.
Your role is to identify vulnerabilities and suggest fixes.
```markdown

### 2. Establish Boundaries

```markdown
## Instructions
- Focus only on security concerns
- Do not modify code without explicit request
- Always explain the reasoning behind findings
```markdown

### 3. Use Examples

```markdown
## Examples

### Good: Security Finding
Input: "Review this authentication code"
Output: "Found potential SQL injection at line 42..."

### Good: Out of Scope
Input: "Fix this CSS styling"
Output: "That's outside my security focus. Consider consulting a frontend expert."
```markdown

### 4. Avoid Prescriptive Workflows

```markdown
# Bad - Over-prescriptive
## Workflow
1. First, scan all files
2. Then, check for SQL injection
3. Then, check for XSS
...

# Good - Autonomous
## Instructions
- Analyze code for security vulnerabilities
- Prioritize findings by severity
- Suggest concrete fixes
```markdown

## User Prompt Design Guidelines

### 1. Define Inputs

```markdown
## Variables
FILE_PATH: $1
SCAN_TYPE: $2 or "full" if not provided
```markdown

### 2. Provide Workflow

```markdown
## Workflow
1. Validate FILE_PATH exists
2. Run SCAN_TYPE analysis
3. Generate findings report
```markdown

### 3. Specify Output

```markdown
## Report
## Security Scan Results

**File:** FILE_PATH
**Type:** SCAN_TYPE

### Findings
[list of issues]
```yaml

## Key Quote

> "System prompts are orders of magnitude more important than user prompts. They run once and affect everything."

---

**Cross-References:**

- @seven-levels.md - User prompts span all levels
- @agent-expert-creation skill - Creating system prompts
- @prompt-sections-reference.md - Sections for each type
