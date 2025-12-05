# Minimum Context Principle

The context engineering philosophy from Lesson 006.

## The Principle

> "You want to context engineer as little as possible. You want the minimum context in your prompt required to solve the problem."

## Why Minimum Context?

### Every Context Adds Variables

Every piece of context you add:

- Increases reasoning complexity
- Adds variables the agent must consider
- Creates potential for distraction
- Competes for attention with the actual task

### Context Pollution

> "Context pollution, context overloading, toxic context - whatever you call it, when you overload the context window, your agent has a harder time focusing on what matters most."

Signs of context pollution:

- Agent addresses tangential concerns
- Responses become unfocused
- Key requirements get missed
- Performance degrades on core task

## The Formula

```text
Effectiveness = Relevance of Context / Volume of Context
```markdown

Maximum effectiveness comes from:

- High relevance (context directly supports the task)
- Low volume (only what's necessary)

## Approaches

### Pre-Loading (Often Wasteful)

Load everything upfront "just in case":

```text
# Pre-loaded context
- Project README (2k tokens)
- API documentation (5k tokens)
- Style guide (3k tokens)
- All utility functions (10k tokens)
- Complete test suite (8k tokens)
= 28k tokens before the actual task
```markdown

### Just-in-Time (Preferred)

Load context only when needed:

```text
# Just-in-time context
1. Start with task description
2. Agent requests specific file → provide it
3. Agent needs API docs → provide relevant section
4. Agent needs test pattern → provide one example
= Only tokens that actually help
```markdown

## Practical Application

### Instead of

```markdown
## Context
Here is the entire codebase structure, all API documentation,
the complete style guide, all existing tests, the project history,
the deployment configuration, and the team's coding standards...

## Task
Add a loading spinner to the submit button.
```markdown

### Do this

```markdown
## Task
Add a loading spinner to the submit button.

## Relevant File
src/components/SubmitButton.tsx

## Pattern Reference
See existing spinner in src/components/LoadingIndicator.tsx
```markdown

## Conditional Documentation Pattern

The solution to context management:

```markdown
# Only load if conditions match

- API docs: When working on API integration
- Style guide: When creating new components
- Test patterns: When writing tests
```markdown

See @conditional-docs-pattern.md for implementation.

## Signs You Have Too Much Context

1. Agent responses are unfocused
2. Agent addresses concerns you didn't ask about
3. Agent misses the core requirement
4. Responses are slower than expected
5. Agent seems "confused" or contradictory

## Signs You Have the Right Amount

1. Agent focuses on the task
2. Responses are direct and relevant
3. No tangential discussions
4. Fast, confident execution
5. Asks for specific context when needed

## Adopt the Agent's Perspective

Before adding context, ask:

> "If I were solving this task with limited attention, would this context help or distract?"

## Related

- @one-agent-one-purpose.md - Focused agents need focused context
- @conditional-docs-pattern.md - Load docs only when conditions match
- @review-vs-test.md - Different tasks need different context
