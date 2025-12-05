# One Agent, One Prompt, One Purpose

The core tactic from Lesson 006: **Let Your Agents Focus**

## The Principle

Specialized agents with focused prompts to achieve a single purpose well.

> "A focused engineer working on a single task is a productive engineer. Agents are the same."

## Why Single-Purpose Agents?

### 1. Full Context Window

When an agent has one purpose, it gets the full context window:

- 200K, 500K, 1M tokens - all for one task
- No competition between objectives
- Maximum reasoning space

### 2. No Context Confusion

Big context windows cause context confusion:

- Multiple objectives compete for attention
- Agent loses focus on what matters most
- Performance drops with complexity

### 3. Reproducible Prompts

Single-purpose prompts can be:

- Committed to your codebase
- Version controlled
- Improved iteratively
- Tested independently

### 4. Creates Evals for Your Agentic Layer

> "By using individualized agents with specific prompts for one purpose, you effectively create evals for the agentic layer of your codebase."

You can:

- Change the model
- Add thinking mode
- Switch agentic coding tools
- Rerun and compare results

## The Three Constraints

As agentic engineers, we have three constraints:

| Constraint | Description |
| ------------ | ------------- |
| **Context Window** | Limited tokens available |
| **Codebase Complexity** | Problem difficulty |
| **Our Abilities** | Skill and expertise |

**Specialized agents bypass TWO of these constraints** (context window and abilities).

## Anti-Pattern: God Model Thinking

Don't expect one agent to do everything:

```text
# BAD: One agent for everything
"Plan the feature, implement it, test it, review it, and document it."

# GOOD: Specialized agents
/plan → plan-agent
/implement → implement-agent
/test → test-agent
/review → review-agent
/document → document-agent
```markdown

## Every Step Requires Different Context

| Step | Question | Required Context |
| ------ | ---------- | ----------------- |
| Plan | What are we building? | Requirements, constraints |
| Build | Did we make it real? | Plan, codebase patterns |
| Test | Does it work? | Test framework, assertions |
| Review | Is it what we asked for? | Spec, implementation |
| Document | How does it work? | Changes, user perspective |

Honor this with dedicated agents for each purpose.

## Commit and Improve

Since prompts are committed:

```text
.claude/commands/
├── plan.md      ← Can improve planning prompt
├── implement.md ← Can improve implementation prompt
├── review.md    ← Can improve review prompt
└── document.md  ← Can improve documentation prompt
```markdown

Each prompt can be:

- Debugged independently
- Improved based on failures
- A/B tested with different approaches
- Shared across projects

## Model Intelligence is Not a Constraint

> "Model intelligence is not a constraint. Don't use this as an excuse. It will set you back. This is a losing mindset."

The model is capable. The question is: are you giving it the right context and focus?

## Related

- @minimum-context-principle.md - Why less context is better
- @review-vs-test.md - Different questions need different agents
- @conditional-docs-pattern.md - Load only what's needed
