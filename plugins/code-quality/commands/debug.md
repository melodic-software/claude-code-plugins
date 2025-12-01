---
description: Root cause analysis using debugger agent for errors, exceptions, and unexpected behavior
argument-hint: [error description or file path]
allowed-tools: Task, Read, Edit, Bash, Glob, Grep
---

# Debug Command

Investigate errors with systematic root cause analysis.

## Instructions

**Use the debugger agent to perform root cause analysis.**

The debugger agent provides:

- **Error message analysis** (stack traces, exceptions)
- **Root cause identification** (tracing back to source)
- **Code flow analysis** (how execution reaches the error)
- **Fix suggestions** (specific, actionable solutions)
- **Verification steps** (how to confirm the fix works)

**Invoke the agent based on the arguments provided:**

```text
$ARGUMENTS

Based on the arguments, determine the debugging scope:

If an error message/stack trace provided:
  - Parse the error to identify type and location
  - Trace back through the code to find root cause
  - Analyze surrounding code for context
  - Suggest fixes with verification steps

If a file path provided:
  - Analyze the file for potential issues
  - Check for common bug patterns
  - Identify error-prone code sections
  - Suggest improvements

If a description provided (e.g., "the API returns 500"):
  - Research the symptom in the codebase
  - Identify potential causes
  - Narrow down to likely root cause
  - Propose investigation steps

If test failure provided:
  - Analyze the failing test
  - Compare expected vs actual behavior
  - Trace the code path being tested
  - Identify what's causing the mismatch
```

## Examples

### Debug an Error Message

```text
/code-quality:debug "TypeError: Cannot read property 'id' of undefined"
/code-quality:debug "Error at src/auth.ts:45: Invalid token format"
```

### Debug a File

```text
/code-quality:debug src/api/users.ts
/code-quality:debug "the authentication middleware"
```

### Debug a Symptom

```text
/code-quality:debug "API returns 500 on login"
/code-quality:debug "tests fail intermittently"
/code-quality:debug "memory usage keeps growing"
```

### Debug Test Failures

```text
/code-quality:debug "test auth.test.ts is failing"
/code-quality:debug "UserService.create test expects 201 but gets 400"
```

## Output Format

The agent returns debugging analysis:

````markdown
## Debug Analysis: [Error/Issue]

### Error Summary
- **Type**: [Error type]
- **Location**: `file:line`
- **Message**: [Error message]

### Root Cause
[Explanation of why this error occurs]

### Code Flow
1. [Step 1 leading to error]
2. [Step 2]
3. [Error occurs here]

### Fix
**File**: `path/to/file.ext`
**Change**: [Specific code change needed]

```language
// Before
[problematic code]

// After
[fixed code]
```

### Verification

1. [How to verify the fix]
2. [Test to run]
3. [Expected outcome]
````

## Command Design Notes

This command delegates to the debugger agent which specializes in error investigation. Unlike the code-reviewer (read-only), the debugger can suggest and help implement fixes since debugging often requires modifications to resolve issues.
