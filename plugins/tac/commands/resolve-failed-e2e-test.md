---
description: Analyze a failed E2E test, fix the underlying issue, and verify the fix
argument-hint: [test-result-json]
---

# Resolve Failed E2E Test

Analyze a failed E2E test, fix the underlying issue, and verify the fix.

## Variables

- `test_result`: $ARGUMENTS - JSON object from /test-e2e command with failed test details

## Input Format

Expects a JSON object from the /test-e2e command:

```json
{
  "test_name": "Basic Query Execution",
  "status": "failed",
  "screenshots": [
    "screenshots/01_initial_state.png",
    "screenshots/02_query_input.png"
  ],
  "error": "Step 8 failed: Results did not appear within 5 seconds"
}
```

## Instructions

### 1. Analyze the E2E Failure

Review the test result:

- **test_name**: Which user journey failed
- **error**: The specific step that failed
- **screenshots**: Visual evidence of state before failure

Extract key information:

- Which step number failed
- What was the expected behavior
- What actually happened
- Visual clues from screenshots

### 2. Locate the Test Specification

Read the original test specification to understand:

- The full user story
- All test steps
- Success criteria
- Context around the failing step

### 3. Analyze Screenshots

Review captured screenshots to:

- Understand application state at failure
- Identify visual anomalies
- Determine if UI elements are present/missing
- Check for error messages on screen

### 4. Identify Root Cause

Common E2E failure causes:

| Symptom | Likely Cause |
| --------- | -------------- |
| Element not found | Selector changed, slow load |
| Wrong text | Logic error, data issue |
| Timeout | Performance issue, missing element |
| Unexpected redirect | Auth issue, error state |
| Missing element | Component not rendering |

### 5. Fix the Issue

Apply fixes based on root cause:

- **UI issue**: Fix component rendering
- **Logic issue**: Fix business logic
- **Timing issue**: Add proper waits/loading states
- **Data issue**: Fix data handling

**IMPORTANT**: Fix the application, not the test (unless test is genuinely incorrect).

### 6. Re-run E2E Test

Execute the original E2E test again:

```text
/test-e2e {original_test_file}
```

**Success criteria**: Test status is "passed"

### 7. Verify No Regressions

Run related E2E tests to ensure fix doesn't break other flows.

## Output Format

Report your resolution:

```markdown
## E2E Resolution Complete

### Failure Analysis
- **Test**: {test_name}
- **Failed Step**: [step number and description]
- **Root Cause**: [what caused the failure]
- **Screenshot Evidence**: [observations from screenshots]

### Fix Applied
- **File(s) Modified**: [list of files]
- **Change Summary**: [brief description]
- **Type of Fix**: [UI/Logic/Performance/Data]

### Validation
- **E2E Test**: PASS
- **Related Tests**: PASS/FAIL
- **New Screenshots**: [paths to verification screenshots]

### Notes
[Any observations or recommendations]
```

## Retry Logic

If the fix doesn't work:

1. Review new screenshots for clues
2. Consider timing/async issues
3. Check for environment-specific problems
4. Apply alternative fix

Maximum 2 retry attempts before escalating (E2E tests are slower).

## Integration with Closed Loop

This command is the **RESOLVE** phase for E2E:

```text
/test-e2e {spec} → [failure JSON] → /resolve-failed-e2e-test {result} → /test-e2e
                                                                            ↓
                                                                     [verify fix]
```
