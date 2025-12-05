# In-Loop vs Out-of-Loop Agentic Coding

Understanding when to use each approach for maximum engineering leverage.

## Two Types of Agentic Coding

### In-Loop

You at your device, prompting back and forth with an agent.

```text
You ←→ Claude Code ←→ Codebase
       (conversation)
```markdown

**Characteristics:**

- Human is active participant
- Real-time feedback loop
- Interactive exploration
- High context, high control

### Out-of-Loop

Agents run autonomously while you're away.

```text
Issue → Trigger → Agent → PR → Review
        (no human until review)
```markdown

**Characteristics:**

- Human defines work, reviews results
- Batch processing
- Templated workflows
- Low presence, high leverage

## Comparison Table

| Aspect | In-Loop | Out-of-Loop |
| -------- | --------- | ------------- |
| **Human role** | Active participant | Define work, review results |
| **Feedback** | Real-time | Asynchronous |
| **Context** | Conversational | Templated |
| **Control** | High | Delegated |
| **Scalability** | Limited by presence | Parallelizable |
| **Best for** | Exploration, learning | Repetitive, well-defined |

## Decision Matrix

| Factor | Choose In-Loop | Choose Out-of-Loop |
| -------- | ---------------- | ------------------- |
| **Problem clarity** | Ambiguous, needs exploration | Well-defined, templatable |
| **Solution confidence** | Uncertain, experimental | High, proven patterns |
| **Iteration needs** | Rapid feedback needed | Batch is acceptable |
| **Risk tolerance** | High risk, needs oversight | Low-medium, testable |
| **Template exists?** | No template for this | Template exists |
| **Domain knowledge** | Learning the domain | Domain is known |
| **Uniqueness** | One-off problem | Problem class |

## When to Use In-Loop

### 1. Exploration and Learning

```text
"I don't know what's causing this bug"
"Help me understand how this module works"
"What's the best approach for this feature?"
```markdown

In-loop lets you:

- Ask clarifying questions
- Explore different approaches
- Build understanding iteratively

### 2. Novel Problems

```text
"We've never built something like this before"
"This is a new architecture pattern for us"
"First time integrating with this API"
```markdown

In-loop lets you:

- Navigate uncertainty together
- Make decisions as information emerges
- Course-correct in real-time

### 3. High-Risk Changes

```text
"This touches critical infrastructure"
"Mistake here could cause data loss"
"Security-sensitive changes"
```markdown

In-loop lets you:

- Review each step
- Catch issues early
- Maintain human judgment in the loop

### 4. Creative Work

```text
"Design a new user experience"
"Write compelling documentation"
"Architect a new system"
```markdown

In-loop lets you:

- Iterate on design
- Provide feedback
- Shape the creative direction

## When to Use Out-of-Loop

### 1. Well-Defined Problem Classes

```text
"Update all dependencies to latest"
"Add CRUD endpoints for new model"
"Fix this specific bug pattern"
```markdown

Out-of-loop excels when:

- Template exists for this work type
- Success criteria are clear
- Validation is automated

### 2. Repetitive Tasks

```text
"Process all issues labeled 'good-first-issue'"
"Run nightly maintenance tasks"
"Handle all dependency update PRs"
```markdown

Out-of-loop excels when:

- Same pattern repeated many times
- Automating saves significant time
- Human review at PR level is sufficient

### 3. Overnight/Weekend Work

```text
"Work on these issues while I sleep"
"Process the backlog over the weekend"
"Handle PRs from other timezones"
```markdown

Out-of-loop excels when:

- Presence is unavailable
- Batch processing is acceptable
- Review can happen later

### 4. Team Scaling

```text
"Let agents handle routine work"
"Free engineers for complex problems"
"Scale without hiring"
```markdown

Out-of-loop excels when:

- Bandwidth is the bottleneck
- Agents can handle the routine
- Humans focus on high-value work

## The Progression Path

Most engineers progress through stages:

```text
Stage 1: Manual coding
         ↓
Stage 2: In-Loop (with AI assistance)
         ↓
Stage 3: Out-of-Loop (AFK agents)
         ↓
Stage 4: Zero Touch Engineering (ZTE)
```markdown

### Stage 1 → Stage 2

**Trigger:** "I should let AI help with this"

**Action:** Start using Claude Code interactively

### Stage 2 → Stage 3

**Trigger:** "I keep doing the same thing over and over"

**Action:** Create templates, set up PITER framework

### Stage 3 → Stage 4

**Trigger:** "The agents are consistently producing good work"

**Action:** Enable auto-merge, skip human review

## Hybrid Approach

Often the best approach is hybrid:

```text
New feature request arrives
         ↓
In-Loop: Design and architect the solution
         ↓
Create template for implementation pattern
         ↓
Out-of-Loop: Implement using template
         ↓
In-Loop: Review and refine
```yaml

## KPI Implications

### In-Loop KPIs

- **Streak**: How many consecutive successes?
- **Attempts**: How many tries to get it right?

Focus: Quality of interaction, learning efficiency

### Out-of-Loop KPIs

- **Presence**: How little can you be involved? (Target: 1)
- **Size**: How large are the work units?

Focus: Leverage, automation, scale

## Quick Decision Guide

```text
Is this a well-defined problem class?
├─ No  → In-Loop (explore first)
└─ Yes → Do you have a template?
         ├─ No  → In-Loop (create template)
         └─ Yes → Out-of-Loop (use ADW)
```markdown

## Common Mistakes

### Over-Automating

**Mistake:** Trying to automate everything immediately

**Fix:** Start with in-loop, graduate to out-of-loop as patterns emerge

### Under-Automating

**Mistake:** Doing repetitive work in-loop forever

**Fix:** Recognize patterns, create templates, build ADWs

### Wrong Mode for Task

**Mistake:** Using out-of-loop for novel/risky work

**Fix:** Match the mode to the task characteristics

## Related Memory Files

- @piter-framework.md - Setting up out-of-loop systems
- @adw-anatomy.md - Structure of autonomous workflows
- @outloop-checklist.md - Deployment readiness
- @agentic-kpis.md - Measuring success in each mode
