---
description: Analyze a failed test, fix the underlying issue, and verify the fix
argument-hint: [test-result-json]
---

# Resolve Failed Test

Analyze a failed test, fix the underlying issue, and verify the fix.

## Variables

- `test_result`: $ARGUMENTS - JSON object from /test command with failed test details

## Input Format

Expects a JSON object from the /test command:

```json
{
  "test_name": "unit_tests",
  "passed": false,
  "execution_command": "pytest tests/test_auth.py -v",
  "test_purpose": "Validates authentication functionality",
  "error": "AssertionError: Expected status 200, got 401"
}
```

## Instructions

### 1. Analyze the Test Failure

Review the test result:

- **test_name**: Which test category failed
- **test_purpose**: What functionality is being validated
- **error**: The specific error message
- **execution_command**: How to reproduce

Identify the root cause by understanding:

- What was expected vs. what happened
- Which code path likely failed
- Possible causes of the error

### 2. Reproduce the Failure

**IMPORTANT**: Use the exact `execution_command` from the test result:

```bash
# Run the exact command to confirm failure
{execution_command}
```

Verify you see the same error. This ensures you're fixing the right problem.

### 3. Fix the Issue

Apply a fix following these principles:

- **Minimal changes**: Fix only what's broken
- **Fix the code, not the test**: Tests verify correctness
- **Preserve existing behavior**: Don't introduce regressions
- **Match existing patterns**: Follow codebase conventions

### 4. Validate the Fix

Re-run the exact same execution_command:

```bash
{execution_command}
```

**Success criteria**: Test now passes (exit code 0, no failures)

### 5. Run Full Validation

If the specific test passes, run the full test suite to check for regressions:

```bash
# Run complete test suite
[full test command]
```

## Output Format

Report your resolution:

```markdown
## Resolution Complete

### Failure Analysis
- **Test**: {test_name}
- **Root Cause**: [What caused the failure]
- **Error**: {error}

### Fix Applied
- **File(s) Modified**: [list of files]
- **Change Summary**: [brief description]

### Validation
- **Specific Test**: PASS
- **Full Suite**: PASS/FAIL
- **Command Used**: {execution_command}

### Notes
[Any observations or recommendations]
```

## Retry Logic

If the fix doesn't work:

1. Re-analyze the error output
2. Consider alternative root causes
3. Apply a different fix
4. Re-validate

Maximum 3 retry attempts before escalating.

## Integration with Closed Loop

This command is the **RESOLVE** phase:

```text
/test → [failure JSON] → /resolve-failed-test {result} → /test
                                                           ↓
                                                    [verify fix]
```
