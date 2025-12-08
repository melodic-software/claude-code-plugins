# ZTE Progression: Three Levels of Agentic Coding

## Overview

Zero-Touch Engineering (ZTE) is the North Star of agentic coding - a codebase that ships itself. Progress through three levels, each reducing your presence KPI.

## Three Levels

| Level | Description | Presence KPI | Your Role |
| ------- | ------------- | -------------- | ----------- |
| **In-Loop** | Interactive prompting, constant back-and-forth | High (constant) | Driver |
| **Out-Loop** | AFK agents, PITER framework, trigger-based | Medium (2: prompt + review) | Commander |
| **Zero-Touch** | Codebase ships itself, automated end-to-end | Low (1: prompt only) | Architect |

## Level 1: In-Loop

**Characteristics:**

- Back-and-forth prompting with agent
- Human intervention at every step
- Agent as assistant, you as driver

**When to use:**

- Learning new codebase
- Complex debugging
- Exploratory work
- Teaching/demonstrating

**Presence KPI:** Constant interaction

## Level 2: Out-Loop

**Characteristics:**

- Trigger workflow and walk away (AFK)
- PITER framework: Prompt -> Implement -> Test -> Review
- Return only to review results
- Agent as executor, you as reviewer

**When to use:**

- Chores, bugs, features with clear specs
- Repetitive tasks
- Batch processing
- Overnight runs

**Presence KPI:** 2 (prompt + review)

See @piter-framework.md for detailed Out-Loop patterns.

## Level 3: Zero-Touch Engineering (ZTE)

**Characteristics:**

- Complete automation including shipping
- No human review required
- Codebase ships itself
- Agent as autonomous system

**When to use:**

- High-confidence problem classes
- After 90%+ success rate achieved
- When review catches nothing
- Chores first, then bugs, then features

**Presence KPI:** 1 (prompt only)

## Progression Path

```text
START: In-Loop (learning, exploring)
       |
       v
PHASE 1: Out-Loop for Chores
         - Low risk, simple changes
         - Build workflow confidence
         |
         v
PHASE 2: Out-Loop for Bugs
         - Medium complexity
         - Test-driven validation
         |
         v
PHASE 3: Out-Loop for Features
         - Full SDLC automation
         - Comprehensive review
         |
         v
PHASE 4: ZTE for Chores
         - Skip review for simple changes
         - Build ZTE confidence
         |
         v
PHASE 5: ZTE for Bugs
         - Tests provide safety net
         - 90%+ confidence achieved
         |
         v
GOAL: ZTE for Features
      - Complete autonomous operation
      - Review becomes bottleneck
```markdown

## Signs You're Ready for Next Level

### Ready for Out-Loop

- [ ] Workflows succeed on first attempt
- [ ] Tests catch issues before you do
- [ ] Spending more time reviewing than fixing
- [ ] Similar tasks repeat frequently

### Ready for ZTE

- [ ] 90%+ Out-Loop success rate
- [ ] Review catches nothing new
- [ ] Human review adds time, not value
- [ ] High confidence in test coverage

## Anti-Patterns

**Staying In-Loop:**

- Constant prompting wastes your time
- You become the bottleneck
- Agents can't scale without autonomy

**Skipping levels:**

- ZTE without Out-Loop experience fails
- Must build confidence incrementally
- Tests and review must prove reliability first

**All-or-nothing thinking:**

- Different problem classes can be at different levels
- Chores can be ZTE while features stay Out-Loop
- Progress incrementally, not globally

## Key Insight

> "The best Out-Loop agent coders have a presence of two. You show up at the prompt and you show up at the review. In the future, you'll realize that you're wasting time reviewing."

The goal isn't to eliminate review entirely - it's to make review unnecessary through reliability.

## Cross-References

- @agentic-kpis.md - KPI metrics for measuring progression
- @piter-framework.md - Out-Loop workflow framework
- @composable-primitives.md - Building blocks for ZTE workflows
- @zte-confidence-building.md - Building confidence for ZTE
