# Issue Severity Classification

How to classify issues from review for appropriate handling.

## Three Severity Levels

### 1. Blocker

**Definition**: Prevents release, must be fixed immediately.

**Characteristics**:

- Will harm user experience
- Feature won't function as expected
- Breaks critical functionality
- Security or data integrity issues

**Examples**:

- Form submission doesn't work
- Data is displayed incorrectly
- Critical button is missing
- Security vulnerability exposed

**Action**: Auto-resolved immediately. Triggers patch workflow.

### 2. Tech Debt

**Definition**: Non-blocking but creates future work.

**Characteristics**:

- Feature works but implementation is suboptimal
- Code quality issues
- Missing optimization
- Incomplete error handling

**Examples**:

- Console warnings in production
- Missing input validation edge cases
- Inefficient database query
- Hardcoded values that should be configurable

**Action**: Documented for future sprint. Release can proceed.

### 3. Skippable

**Definition**: Polish items that can be ignored.

**Characteristics**:

- Minor visual imperfections
- Nice-to-have improvements
- Subjective preferences
- Non-functional enhancements

**Examples**:

- Slight color mismatch
- Animation could be smoother
- Extra whitespace in layout
- Could add tooltip for clarity

**Action**: Noted but no action required. Release proceeds.

## Classification Guidelines

### Ask These Questions

1. **Does it block the feature from working?** → Blocker
2. **Will users notice and be negatively affected?** → Blocker
3. **Is it a quality issue but feature works?** → Tech Debt
4. **Is it a preference or polish item?** → Skippable

### Decision Tree

```text
Is the feature functional?
├── No → BLOCKER
└── Yes → Does it harm UX significantly?
          ├── Yes → BLOCKER
          └── No → Will it cause problems later?
                    ├── Yes → TECH_DEBT
                    └── No → SKIPPABLE
```markdown

## Review JSON Structure

```json
{
  "success": true,
  "review_summary": "Feature implemented correctly with minor issues",
  "review_issues": [
    {
      "issue_description": "Submit button doesn't disable during loading",
      "issue_resolution": "Add disabled state during form submission",
      "issue_severity": "blocker"
    },
    {
      "issue_description": "Console warning about missing key prop",
      "issue_resolution": "Add key prop to list items",
      "issue_severity": "tech_debt"
    },
    {
      "issue_description": "Could add hover effect to cards",
      "issue_resolution": "Add subtle hover animation",
      "issue_severity": "skippable"
    }
  ]
}
```markdown

## Success Criteria

Review **succeeds** (success: true) when:

- No blocker issues exist
- Feature matches specification
- Core functionality works

Review can succeed with tech_debt and skippable issues.

## Auto-Resolution Flow

```text
Review
  ├── Blockers found?
  │     ├── Yes → Create patch → Implement → Re-review
  │     └── No → Success
  │
  ├── Tech debt found?
  │     └── Document for future
  │
  └── Skippable found?
        └── Note but ignore
```markdown

## Retry Limits

Auto-resolution has retry limits:

- Maximum 3 review attempts
- Each attempt can create patches
- If blockers persist after 3 tries, escalate to human

## Common Misclassifications

### Over-classifying as Blocker

```text
"Font size is 14px instead of 16px" → This is SKIPPABLE, not blocker
"Button color is slightly different" → This is SKIPPABLE
```markdown

### Under-classifying as Skippable

```text
"Form doesn't validate email" → This is BLOCKER if it causes errors
"API returns wrong data" → This is BLOCKER
```markdown

## Think About Impact

> "Think hard about the impact of the issue on the feature and the user."

Classification should reflect real-world impact:

- Will users notice?
- Will it cause frustration?
- Will it cause data issues?
- Will it cause support tickets?

## Related

- @review-vs-test.md - Review identifies these issues
- @closed-loop-anatomy.md - Resolution is part of the loop
- @one-agent-one-purpose.md - Review agent focuses on classification
