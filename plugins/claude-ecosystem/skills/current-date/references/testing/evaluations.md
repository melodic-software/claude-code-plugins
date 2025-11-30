# Skill Evaluations

Structured evaluation scenarios for testing the current-date skill.

## Evaluation 1: Basic date request

```json
{
  "skills": ["current-date"],
  "query": "What's the current UTC date?",
  "files": [],
  "expected_behavior": [
    "Skill activates autonomously without explicit invocation",
    "Executes `date -u` bash command (not stating from memory)",
    "Returns actual command output in ISO 8601 format YYYY-MM-DD HH:MM:SS UTC",
    "Includes day of week in parentheses"
  ]
}
```

## Evaluation 2: Task start verification

```json
{
  "skills": ["current-date"],
  "query": "I'm starting a new task, need to verify the date first",
  "files": [],
  "expected_behavior": [
    "Skill activates based on 'starting tasks' trigger",
    "Executes date command immediately",
    "Provides verified date before user proceeds with task"
  ]
}
```

## Evaluation 3: Execution vs reference context

```json
{
  "skills": ["current-date"],
  "query": "Get today's date",
  "files": [],
  "expected_behavior": [
    "Skill recognizes execution context (not reference/guidance)",
    "Immediately executes date command",
    "Does NOT explain how to get date without executing command",
    "Returns actual verified current date"
  ]
}
```

## Test Scenarios (Quick Reference)

### Scenario 1: Basic date request

- Query: "What's the current UTC date?"
- Expected: Skill activates, runs `date -u` command, returns formatted output

### Scenario 2: Task start verification

- Query: "I'm starting a new task, need to verify the date first"
- Expected: Skill activates autonomously based on "starting tasks" trigger

### Scenario 3: Skill composition

- Context: Another skill (e.g., markdown-linting) invokes current-date
- Expected: Successful activation and date return

---

**Parent:** [SKILL.md](../../SKILL.md)
