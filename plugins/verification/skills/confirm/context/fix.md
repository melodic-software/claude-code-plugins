# Fix Confirmation Mode

Structured confirmation that a bug fix actually resolves the reported issue. Core question: "Is the original symptom gone, and did the fix introduce anything new?"

## When to use

- A bug was reported and a fix was implemented
- User asks "is this fixed?" or "does this resolve the issue?"
- `/testing:diagnose` (reproduce-fix-retest-regression) cycle completed and needs summary evidence

## Process

### 1. Restate the original problem

Find the bug report, error message, or symptom description in the conversation. Restate clearly:

- **What was happening?** (symptom)
- **What should have been happening?** (expected behavior)
- **Under what conditions?** (reproduction steps)

If the original problem description is vague, ask user to clarify before proceeding.

### 2. Confirm the fix addresses the root cause

The fix should address ROOT CAUSE, not the symptom:

- **Root cause fix**: "Null check was missing because the query returned null for deleted users" → added null handling in the query
- **Symptom fix**: "Added a try-catch around the null reference exception" → exception is suppressed but underlying issue persists

If the fix appears to be a symptom fix rather than a root cause fix, flag it.

### 3. Evidence checklist

| Evidence type | Source | Status |
|--------------|--------|--------|
| **Reproduction test** | A test that fails on the pre-fix code and passes on the fix | Required |
| **Regression tests** | All existing tests still pass | Required |
| **Root cause identified** | Explanation of WHY the bug occurred | Required |
| **Fix is minimal** | Only the necessary change was made, no unrelated changes | Recommended |
| **Sibling check** | Similar code paths checked for the same bug pattern | Recommended |

### 4. Verify the reproduction test

Gold standard for fix confirmation is a test that:

1. **Fails** when run against pre-fix code (proves the bug exists)
2. **Passes** when run against fixed code (proves the fix works)

If `/testing:diagnose` was used, this test should already exist. Reference it by name:

```
Reproduction test: returns_null_when_user_is_deleted  # name it per your framework's convention
- Fails on commit abc1234 (pre-fix): the reported failure (e.g. a null-dereference crash)
- Passes on commit def5678 (post-fix): returns null as expected
```

If no reproduction test exists, flag this as a gap.

### 5. Verify regression

All existing tests must still pass. Reference the Stage 1 mechanical-prerequisite results from `/verification:confirm`.

Pay special attention to tests in same module or feature area as the fix — these are most likely affected by unintended side effects.

### 6. Report

```
## Fix Confirmation

### Original Problem
- **Symptom**: <what was happening>
- **Expected**: <what should have been happening>
- **Conditions**: <reproduction steps>

### Root Cause
<what caused the bug and why>

### Fix Applied
- **Files changed**: <list>
- **Approach**: <what the fix does>
- **Root cause vs symptom**: ROOT CAUSE / SYMPTOM ONLY

### Evidence
| Check | Status | Details |
|-------|--------|---------|
| Reproduction test exists | PASS/FAIL | <test name> |
| Reproduction test fails pre-fix | PASS/FAIL/NOT VERIFIED | <evidence> |
| Reproduction test passes post-fix | PASS/FAIL | <evidence> |
| All existing tests pass | PASS/FAIL | <from Stage 1 results> |
| Fix is minimal (no unrelated changes) | PASS/FAIL | <assessment> |
| Sibling code paths checked | PASS/SKIP | <findings> |

### Sibling Check
<did the same pattern exist elsewhere? If so, were those instances fixed too?>
```

### 7. Verdict

- **CONFIRMED** if reproduction test passes, regressions pass, and root cause is addressed
- **PARTIALLY CONFIRMED** if symptom is resolved but root cause is uncertain or siblings weren't checked
- **NOT CONFIRMED** if no reproduction test exists, or existing tests fail, or fix is symptom-only
