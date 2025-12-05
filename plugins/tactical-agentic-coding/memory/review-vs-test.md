# Review vs Test

Understanding the critical distinction between testing and reviewing.

## The Core Questions

| Phase | Question |
| ------- | ---------- |
| **Testing** | "Does it work?" |
| **Review** | "Is what we built what we asked for?" |

These are fundamentally different questions that require different approaches.

## Why Both Are Needed

### Testing Validates Functionality

Tests check that code executes correctly:

- Functions return expected values
- APIs respond with correct status codes
- Components render without errors
- Edge cases are handled

```text
Input: user clicks submit
Expected: form data is sent to API
Result: PASS - form data was sent
```markdown

### Review Validates Alignment

Review checks that implementation matches the specification:

- Features match requirements
- UI matches design
- Behavior matches user story
- Nothing was missed or misinterpreted

```text
Spec: "Add dark mode toggle in settings"
Implementation: Toggle added to header
Review: FAIL - Toggle is in wrong location
```yaml

## The Gap Tests Don't Catch

A feature can:

- Pass all tests ✓
- Build successfully ✓
- Have no errors ✓
- **Still not match what was requested** ✗

Example:

```text
Spec: "Export to CSV with column headers"
Implementation: Export to CSV without headers
Tests: All pass (exports work, file is valid CSV)
Review: FAIL - Missing required headers
```markdown

## Different Agents for Different Questions

### Test Agent

**Purpose**: Verify functionality
**Tools**: Test runners, assertion frameworks
**Output**: Pass/fail results with errors
**Context**: Test framework, function signatures

### Review Agent

**Purpose**: Verify alignment with spec
**Tools**: File reading, screenshot capture
**Output**: Issues classified by severity
**Context**: Specification, implementation diff

## The SDLC Questions

| Step | Question | Purpose |
| ------ | ---------- | --------- |
| **Plan** | What are we building? | Define requirements |
| **Build** | Did we make it real? | Implement solution |
| **Test** | Does it work? | Validate functionality |
| **Review** | Is it what we planned? | Validate alignment |
| **Document** | How does it work? | Create reference |

## Review Captures Proof

Testing returns pass/fail. Review captures evidence:

- **Screenshots** showing actual behavior
- **Comparisons** against specification
- **Issues** with severity classification
- **Visual proof** for stakeholders

## Severity Classification

Review issues are classified by impact:

| Severity | Description | Action |
| ---------- | ------------- | -------- |
| **blocker** | Prevents release, harms UX | Must fix now |
| **tech_debt** | Creates future work | Document, fix later |
| **skippable** | Polish items | Can ignore |

Only blockers trigger auto-resolution.

## When to Use Each

### Use Testing When

- Verifying code correctness
- Checking edge cases
- Validating API contracts
- Ensuring no regressions

### Use Review When

- Comparing against specification
- Verifying visual appearance
- Checking feature completeness
- Validating user experience

## Integration in Workflow

```text
/plan    → What are we building?
/build   → Make it real
/test    → Does it work?
/review  → Is it what we asked for?
/patch   → Fix blockers
/document → How does it work?
```markdown

Both test and review are essential. Neither replaces the other.

## Related

- @closed-loop-anatomy.md - Feedback loops for both test and review
- @one-agent-one-purpose.md - Different questions need different agents
- @issue-severity-classification.md - How to classify review issues
