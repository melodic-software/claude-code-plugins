# Hook Timing Philosophy

This document provides guidance on when to use different hook event types to maximize agent effectiveness while maintaining guardrails.

## Core Principle

**Blocking agent mid-plan disrupts coherent execution.** Prefer validation at natural boundaries (commit time, session end) over interrupting mid-operation.

When a hook blocks an operation mid-execution, the agent may:

- Lose track of its multi-step plan
- Retry the same operation repeatedly
- Become "confused" about what was and wasn't completed
- Waste tokens on recovery attempts

## Hook Timing Options

| Event            | When It Fires                    | Blocking Effect             | Best For                        |
| ---------------- | -------------------------------- | --------------------------- | ------------------------------- |
| PreToolUse       | Before tool executes             | Stops operation             | Security-critical checks        |
| PostToolUse      | After tool completes             | Can auto-fix or warn        | Style, formatting, linting      |
| UserPromptSubmit | Before agent processes prompt    | Blocks agent start          | Pre-validation, context hints   |
| SessionStart     | When session begins              | None (informational)        | Context injection, setup        |
| SessionEnd       | When session ends                | None (informational)        | Cleanup, logging                |
| PreCompact       | Before context compaction        | None (informational)        | State preservation              |
| Stop             | When agent stops                 | None (informational)        | Final logging                   |

## Recommended Patterns

### Block-at-Submit (Preferred for Validation)

Use PreToolUse on commit operations rather than write operations:

```text
Agent flow with block-at-submit:
1. Agent writes files freely
2. Agent iterates on changes
3. Agent attempts commit -> Hook validates
4. If validation fails -> Agent fixes and retries
5. If validation passes -> Commit succeeds
```

**Why this works:**

- Agent completes coherent work units before validation
- Natural retry boundary (commit is a clear checkpoint)
- Agent understands "commit failed, fix and retry"
- Fewer confusing mid-operation interruptions

**Implementation:**

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "bash validate-before-commit.sh"
        }
      ]
    }
  ]
}
```

The validation script checks if the command is a `git commit` and validates accordingly.

### Auto-Fix (Preferred for Style)

Use PostToolUse to automatically fix issues after writes:

```text
Agent flow with auto-fix:
1. Agent writes file
2. PostToolUse hook runs linter with --fix
3. File is automatically corrected
4. Agent continues uninterrupted
```

**Why this works:**

- Agent never sees the "error" - it's handled automatically
- No confusion or retry loops
- Consistent code style without agent overhead
- Agent can focus on logic, not formatting

**Implementation:**

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "bash auto-lint.sh"
        }
      ]
    }
  ]
}
```

### Block-at-Write (Use Sparingly)

Only use PreToolUse blocking on Write/Edit for security-critical checks:

**Appropriate uses:**

- Preventing credential exposure in files
- Blocking writes to protected paths
- Stopping creation of dangerous file types

**Avoid for:**

- Style/formatting issues (use PostToolUse auto-fix)
- Lint errors (use PostToolUse)
- Convention violations (use PostToolUse or commit-time)

## Decision Tree

```text
What are you validating?
|
|-- Security-critical (credentials, protected paths)?
|   +-- Use PreToolUse blocking on Write/Edit
|
|-- Style, formatting, linting?
|   +-- Use PostToolUse with auto-fix
|
|-- Code quality, tests, comprehensive checks?
|   +-- Use PreToolUse on git commit (block-at-submit)
|
|-- Context hints, reminders?
|   +-- Use UserPromptSubmit (non-blocking)
|
+-- Logging, auditing?
    +-- Use any event with exit 0 (non-blocking)
```

## Pattern Examples

### Security: Block Credential Writes

```bash
#!/bin/bash
# PreToolUse hook - appropriate for security

# Check if writing credentials
if echo "$TOOL_INPUT" | grep -qE "(api_key|password|secret).*=.*['\"][^'\"]+['\"]"; then
  echo '{"decision": "block", "reason": "Potential credential in file content"}'
  exit 0
fi

echo '{"decision": "allow"}'
```

### Style: Auto-Fix on Write

```bash
#!/bin/bash
# PostToolUse hook - appropriate for style

FILE_PATH="$1"

# Only process markdown files
if [[ "$FILE_PATH" == *.md ]]; then
  # Auto-fix without blocking
  npx markdownlint-cli2 --fix "$FILE_PATH" 2>/dev/null || true
fi

# Always exit 0 - auto-fix is best-effort
exit 0
```

### Quality: Block at Commit

```bash
#!/bin/bash
# PreToolUse hook on Bash - appropriate for quality gates

# Only check git commit commands
if ! echo "$TOOL_INPUT" | grep -q "git commit"; then
  echo '{"decision": "allow"}'
  exit 0
fi

# Run tests
if ! npm test; then
  echo '{"decision": "block", "reason": "Tests must pass before commit"}'
  exit 0
fi

echo '{"decision": "allow"}'
```

## Migration Guide

### Moving from Block-at-Write to Block-at-Submit

1. **Identify non-security hooks** that currently block on Write/Edit
2. **Change matcher** from `Write|Edit` to `Bash`
3. **Update hook logic** to only trigger on `git commit` commands
4. **Test** that agent can iterate freely and validation happens at commit

### Moving from Block to Auto-Fix

1. **Change event** from PreToolUse to PostToolUse
2. **Update hook** to fix instead of block
3. **Always exit 0** - auto-fix should be best-effort
4. **Test** that agent continues uninterrupted

## Summary

| Validation Type     | Recommended Event | Blocking | Pattern           |
| ------------------- | ----------------- | -------- | ----------------- |
| Security-critical   | PreToolUse        | Yes      | Block immediately |
| Style/formatting    | PostToolUse       | No       | Auto-fix          |
| Code quality        | PreToolUse (Bash) | Yes      | Block at commit   |
| Context/hints       | UserPromptSubmit  | No       | Inject context    |
| Logging/audit       | Any               | No       | Exit 0 always     |

**Remember:** The goal is effective guardrails with minimal agent disruption. Block at natural boundaries, auto-fix when possible, and reserve mid-operation blocking for true security requirements.

---

**Last Updated:** 2025-11-30
