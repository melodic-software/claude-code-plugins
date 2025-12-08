# Closed Loop Anatomy

The core tactic from Lesson 005: **Always Add Feedback Loops**

## The Problem

Without feedback loops, agents operate "open loop" - they execute tasks without verification. This leads to:

- Silent failures
- Cascading errors
- Human intervention required to catch mistakes
- Unpredictable reliability

## The Solution: Closed Loop Prompts

A closed loop prompt has three phases that form a cycle:

```text
┌─────────────────────────────────────┐
│                                     │
│   REQUEST → VALIDATE → RESOLVE      │
│       ↑                    │        │
│       └────────────────────┘        │
│                                     │
└─────────────────────────────────────┘
```markdown

### Phase 1: REQUEST

Ask the agent to perform a task with clear success criteria.

```text
REQUEST: Run the test suite and report results
SUCCESS CRITERIA: All tests pass with exit code 0
```markdown

### Phase 2: VALIDATE

Check if the task succeeded using deterministic validation.

```text
VALIDATE: Execute `pytest -v` and capture output
CHECK: Exit code == 0 AND no "FAILED" in output
```markdown

### Phase 3: RESOLVE

If validation fails, take corrective action and re-validate.

```text
IF validation failed:
  1. Analyze the failure
  2. Identify root cause
  3. Apply fix
  4. Return to VALIDATE phase
```markdown

## Template Pattern

```markdown
## Closed Loop: [Operation Name]

### Request
[What task should the agent perform?]

### Validate
[How do we know if it succeeded?]
- Command: [validation command]
- Success: [what success looks like]
- Failure: [what failure looks like]

### Resolve
[What to do if validation fails]
1. Analyze: [how to understand the failure]
2. Fix: [how to address the issue]
3. Re-validate: [run validation again]
```markdown

## Common Closed Loop Types

### Test-Driven Loop

```text
REQUEST: Implement feature X
VALIDATE: Run pytest, all tests pass
RESOLVE: Fix failing tests, re-run
```markdown

### Type-Check Loop

```text
REQUEST: Add new function
VALIDATE: Run tsc --noEmit, no errors
RESOLVE: Fix type errors, re-run
```markdown

### Lint Loop

```text
REQUEST: Write code
VALIDATE: Run linter, no warnings
RESOLVE: Apply lint fixes, re-run
```markdown

### Build Loop

```text
REQUEST: Make changes
VALIDATE: Run build, succeeds
RESOLVE: Fix build errors, re-run
```markdown

### E2E Loop

```text
REQUEST: Implement user flow
VALIDATE: Run E2E test, all steps pass
RESOLVE: Fix failing steps, re-run
```markdown

## Why This Matters

1. **Self-Correction**: Agents can fix their own mistakes
2. **Reliability**: Validation catches errors before delivery
3. **Reduced Human Intervention**: Loop continues until success
4. **Determinism**: Clear pass/fail criteria remove ambiguity
5. **Confidence**: Validation proves correctness

## Anti-Pattern: Open Loop

```text
REQUEST: Implement feature X
[No validation]
[No resolution path]
DONE: Hope it works
```markdown

This is the #1 cause of unreliable agent behavior.

## Related

- @test-leverage-point.md - Why tests are the ultimate validation
- @validation-commands.md - Patterns for validation commands
- @e2e-test-patterns.md - E2E testing for complex flows
