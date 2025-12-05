# E2E Test Runner

Execute an end-to-end test specification and report results.

## Variables

- `e2e_test_file`: $1 - Path to the E2E test specification file

## Instructions

1. **Read the Test Specification**: Load and parse the e2e_test_file
2. **Digest the User Story**: Understand what user journey is being tested
3. **Execute Test Steps**: Perform each step in sequence
4. **Verify Checkpoints**: Check all `**Verify**` steps carefully
5. **Capture Screenshots**: Save screenshots as specified in the test
6. **Report Results**: Return structured JSON output

## Execution Process

For each step in the test specification:

1. Read the step instruction
2. Execute the action (navigate, click, enter, etc.)
3. If step contains `**Verify**`:
   - Check the condition
   - If fails, mark test as failed and stop
4. If step says "Take screenshot":
   - Capture current state
   - Save to screenshots directory

## Success Criteria Validation

After all steps complete:

- Review the Success Criteria section
- Verify each criterion is met
- If any criterion fails, mark test as failed

## Output Format

Return ONLY a JSON object:

**Passed:**

```json
{
  "test_name": "Basic Query Execution",
  "status": "passed",
  "screenshots": [
    "screenshots/01_initial_state.png",
    "screenshots/02_query_input.png",
    "screenshots/03_results.png"
  ],
  "error": null
}
```markdown

**Failed:**

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
```markdown

## Result Structure

| Field | Description |
| ------- | ------------- |
| `test_name` | Name from the test specification |
| `status` | "passed" or "failed" |
| `screenshots` | Array of screenshot paths captured |
| `error` | Error description if failed, null if passed |

## Integration with Closed Loop

This command is the **REQUEST** phase for E2E validation:

```text
/test-e2e {spec} → [JSON result] → /resolve-failed-e2e-test {result}
```markdown

## Example Usage

```text
/test-e2e .claude/commands/e2e/test-basic-query.md
```text
