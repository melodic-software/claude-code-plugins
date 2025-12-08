---
name: model-selection
description: Choose appropriate model for custom agent tasks. Use when selecting between Haiku, Sonnet, and Opus for agents, optimizing cost vs quality tradeoffs, or matching model capability to task complexity.
version: 1.0.0
allowed-tools: Read, Grep, Glob
tags: [model, haiku, sonnet, opus, cost, performance, selection]
---

# Model Selection Skill

Choose the right model for custom agent tasks based on complexity, cost, and performance requirements.

## Purpose

Guide selection of appropriate Claude model (Haiku, Sonnet, Opus) for custom agent tasks to optimize cost, speed, and quality.

## When to Use

- Designing a new custom agent
- Optimizing existing agent performance
- Balancing cost vs quality
- Meeting specific latency requirements

## Model Overview

| Model | Speed | Cost | Quality | Use Case |
| ------- | ------- | ------ | --------- | ---------- |
| **Haiku** | Fastest | Lowest | Good | Simple tasks, high volume |
| **Sonnet** | Fast | Medium | Very Good | Most tasks, balanced |
| **Opus** | Slowest | Highest | Best | Complex reasoning |

## Selection Decision Tree

```text
START
  │
  ├── Is task simple transformation?
  │   └── YES → Haiku
  │
  ├── Is cost the primary concern?
  │   └── YES → Haiku (if adequate) or Sonnet
  │
  ├── Is quality critical (no room for error)?
  │   └── YES → Opus
  │
  ├── Does task require complex reasoning?
  │   └── YES → Opus
  │
  ├── Is latency critical (real-time)?
  │   └── YES → Haiku
  │
  └── DEFAULT → Sonnet (best balance)
```

## Model Selection by Task Type

### Haiku Tasks

Best for:

- Text transformations (uppercase, formatting)
- Simple classification
- Data extraction
- High-volume operations
- Real-time processing
- Pattern matching

```python
# Haiku examples
model="claude-3-5-haiku-20241022"

# Echo agent - simple transformation
# Calculator - straightforward math
# Stream processor - high volume, low complexity
```markdown

### Sonnet Tasks

Best for:

- Code generation
- Code review
- Planning and analysis
- Most custom agents
- Balanced performance

```python
# Sonnet examples
model="claude-sonnet-4-20250514"

# QA agent - codebase analysis
# Builder agent - code implementation
# General-purpose agents
```markdown

### Opus Tasks

Best for:

- Strategic planning
- Complex architectural decisions
- Critical code review
- Multi-step reasoning
- Novel problem solving

```python
# Opus examples
model="claude-opus-4-20250514"

# Planner agent - strategic decisions
# Reviewer agent - critical validation
# Architect agent - system design
```markdown

## Cost Considerations

### Relative Costs

| Model | Input Tokens | Output Tokens | Relative Cost |
| ------- | -------------- | --------------- | --------------- |
| Haiku | Low | Low | 1x |
| Sonnet | Medium | Medium | ~10x |
| Opus | High | High | ~30x |

### Cost Optimization Strategies

1. **Start with Haiku**: Test if simpler model is adequate
2. **Use Haiku for preprocessing**: Filter/classify before main task
3. **Reserve Opus for critical paths**: Only where quality is paramount
4. **Monitor costs**: Track `ResultMessage.total_cost_usd`

```python
# Cost tracking
async for message in client.receive_response():
    if isinstance(message, ResultMessage):
        print(f"Query cost: ${message.total_cost_usd:.6f}")
```markdown

## Speed Considerations

### Latency Profiles

| Model | First Token | Total Time | Throughput |
| ------- | ------------- | ------------ | ------------ |
| Haiku | ~500ms | Fast | Highest |
| Sonnet | ~1s | Medium | Good |
| Opus | ~2s | Slower | Lower |

### Speed Optimization

1. **Real-time needs Haiku**: Sub-second response
2. **Interactive needs Sonnet**: Acceptable latency
3. **Batch allows Opus**: Latency less critical

## Quality Considerations

### Capability Differences

| Capability | Haiku | Sonnet | Opus |
| ------------ | ------- | -------- | ------ |
| Simple reasoning | ✓ | ✓ | ✓ |
| Code generation | Limited | Good | Excellent |
| Complex planning | Poor | Good | Excellent |
| Multi-step reasoning | Limited | Good | Excellent |
| Novel problems | Poor | Adequate | Excellent |

### Quality Requirements

- **Haiku**: Acceptable for well-defined, simple tasks
- **Sonnet**: Good for most development tasks
- **Opus**: Required for critical decisions

## Multi-Model Patterns

### Tiered Processing

```python
# Tier 1: Haiku for classification
classification = await classify_task(task, model="haiku")

# Tier 2: Route to appropriate model
if classification == "simple":
    result = await process(task, model="haiku")
elif classification == "complex":
    result = await process(task, model="opus")
else:
    result = await process(task, model="sonnet")
```markdown

### Multi-Agent with Different Models

```python
# Planner: Opus for strategic decisions
planner_options = ClaudeAgentOptions(
    model="claude-opus-4-20250514"
)

# Builder: Sonnet for implementation
builder_options = ClaudeAgentOptions(
    model="claude-sonnet-4-20250514"
)

# Reviewer: Opus for critical review
reviewer_options = ClaudeAgentOptions(
    model="claude-opus-4-20250514"
)
```markdown

## Output Format

When recommending model selection:

```markdown
## Model Selection

**Task:** [description]
**Recommended Model:** [Haiku/Sonnet/Opus]

### Decision Factors

| Factor | Weight | Assessment |
| -------- | -------- | ------------ |
| Complexity | [H/M/L] | [assessment] |
| Cost sensitivity | [H/M/L] | [assessment] |
| Quality requirement | [H/M/L] | [assessment] |
| Latency requirement | [H/M/L] | [assessment] |

### Rationale

[Why this model is appropriate]

### Alternatives

- If cost is concern: [alternative]
- If quality is critical: [alternative]

### Configuration

```python
options = ClaudeAgentOptions(
    model="[model-id]",
    ...
)
```text

```

## Selection Checklist

- [ ] Task complexity assessed
- [ ] Cost constraints identified
- [ ] Quality requirements defined
- [ ] Latency requirements considered
- [ ] Model selected with rationale
- [ ] Alternatives documented

## Key Insights

> "Choose wisely: Claude Haiku for simple, fast tasks. Claude Sonnet for balanced performance. Claude Opus for complex reasoning."

Model selection directly impacts:

- User experience (latency)
- Operational cost (tokens)
- Output quality (accuracy)

## Cross-References

- @core-four-custom.md - Model in Core Four
- @custom-agent-design skill - Agent design workflow
- @agent-deployment-forms.md - Deployment considerations
