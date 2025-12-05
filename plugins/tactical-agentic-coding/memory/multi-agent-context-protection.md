# Multi-Agent Context Protection

R&D framework applied at scale - keeping contexts clean across fleets.

## The Challenge

In multi-agent systems, context can quickly become:

- **Polluted**: Irrelevant information from other agents
- **Bloated**: Too much detail in orchestrator
- **Contaminated**: Mixed concerns across agents

## R&D Framework at Scale

### Reduce (Orchestrator)

Keep orchestrator context minimal:

- Only orchestration logic
- No file contents
- No code details
- No technical specifics
- High-level progress only

### Delegate (Agents)

Let specialized agents hold details:

- Scouts hold codebase knowledge
- Builders hold implementation details
- Reviewers hold analysis
- Each context is focused

## Context Boundaries

### What Orchestrator Holds

```text
Orchestrator Context:
├── Task understanding
├── Agent management state
├── High-level progress
├── Result summaries
└── Final aggregation

NOT in Orchestrator:
├── File contents
├── Code snippets
├── Technical details
└── Implementation specifics
```markdown

### What Agents Hold

```text
Scout Context:
├── Codebase structure
├── File contents (relevant)
├── Pattern analysis
└── Findings

Builder Context:
├── Implementation specs
├── Code being written
├── Test results
└── Build output

Reviewer Context:
├── Code diffs
├── Analysis results
├── Issue findings
└── Recommendations
```markdown

## Anti-Pattern: Orchestrator Doing Work

**Wrong**:

```text
User: "Add rate limiting to auth"
Orchestrator: *reads auth files directly*
Orchestrator: *writes rate limiting code*
Orchestrator: *runs tests*
```yaml

Problems:

- Orchestrator context bloats
- Single point of failure
- Can't scale
- No specialization

**Correct**:

```text
User: "Add rate limiting to auth"
Orchestrator: create_agent("scout", "analyze auth module")
Orchestrator: create_agent("builder", "implement based on scout report")
Orchestrator: create_agent("reviewer", "verify implementation")
Orchestrator: aggregate_results()
```yaml

Benefits:

- Orchestrator stays lean
- Parallel execution possible
- Specialized agents
- Clean context boundaries

## Context Isolation Patterns

### Agent Scoping

Each agent is scoped to one orchestrator:

- Can't access other orchestrator's agents
- Results don't leak across boundaries
- Clean isolation

### Fresh Agent Pattern

Create fresh agents for each task:

- No context carryover
- Clean slate
- No contamination
- Delete when done

### Result Summarization

Pass summaries, not raw data:

- Scout produces summary, not all file contents
- Builder reports changes, not implementation details
- Reviewer lists issues, not full analysis

## Implementation Patterns

### Prompt for Context Protection

```text
You are an orchestrator. You manage other agents.

IMPORTANT: You do NOT do work directly.
- Do NOT read files yourself
- Do NOT write code yourself
- Do NOT run commands yourself

Instead:
- Create specialized agents
- Command them with detailed prompts
- Monitor their progress
- Aggregate their results
```markdown

### Result Aggregation

```text
When aggregating results:
- Extract key findings
- Note produced assets
- Summarize status
- Report metrics

Do NOT include:
- Full file contents
- Complete code blocks
- Raw logs
- Technical details
```markdown

## Context Budget Management

### Per-Agent Budgets

| Agent Type | Context Target |
| ------------ | --------------- |
| Scout (fast) | < 10K tokens |
| Builder | < 50K tokens |
| Reviewer | < 30K tokens |
| Orchestrator | < 20K tokens |

### Monitoring Context

Track context usage:

- Alert when approaching limits
- Summarize long contexts
- Clear completed work
- Archive old results

## Key Insight

> "The orchestrator's power comes from NOT doing the work. By delegating to specialized agents with focused contexts, you can scale beyond any single context window."

## Anti-Patterns

| Anti-Pattern | Problem | Solution |
| -------------- | --------- | ---------- |
| Orchestrator reading files | Context bloat | Delegate to scouts |
| Passing full file contents | Token waste | Pass summaries |
| Reusing agents | Context contamination | Fresh agents |
| Global context | No isolation | Scoped contexts |
| Orchestrator coding | Wrong role | Delegate to builders |

## Cross-References

- @rd-framework.md - Original R&D framework
- @context-layers.md - Context layer hierarchy
- @three-pillars-orchestration.md - Full framework
- @single-interface-pattern.md - Orchestrator architecture
