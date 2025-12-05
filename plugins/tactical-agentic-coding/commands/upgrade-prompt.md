---
description: Upgrade an existing prompt to a higher level
argument-hint: [prompt-path] [target-level]
---

# Upgrade Prompt

Upgrade an existing prompt to a higher level.

## Arguments

- `$1`: Path to prompt file
- `$2`: Target level (optional, defaults to current + 1)

## Instructions

You are upgrading a prompt to add capabilities from a higher level.

### Step 1: Validate Inputs

If no `$1` provided, STOP and ask user for prompt file path.

### Step 2: Read Current Prompt

Read the prompt file at `$1` completely.

### Step 3: Analyze Current Level

Identify current level based on:

- Sections present
- Patterns used
- Complexity indicators

### Step 4: Determine Target Level

Target = `$2` if provided, otherwise current + 1.

Validate:

- Target must be > current
- Target must be <= 7
- If target is > current + 2, warn about complexity jump

### Step 5: Identify Additions Needed

For each level jump:

| From | To | Add |
| ------ | ---- | ----- |
| 1 | 2 | Variables, Workflow, Report |
| 2 | 3 | Control Flow (conditionals, loops, STOP) |
| 3 | 4 | Delegation (Task tool patterns) |
| 4 | 5 | Accept prompt file as input |
| 5 | 6 | Template/Specified Format section |
| 6 | 7 | Expertise section, self-improvement |

### Step 6: Transform the Prompt

Apply additions:

**Level 1 -> 2:**

- Add Variables section with dynamic/static vars
- Convert instructions to numbered Workflow
- Add Report section

**Level 2 -> 3:**

- Add STOP conditions to Workflow
- Add `<loop-tags>` where iteration needed
- Add conditional branching

**Level 3 -> 4:**

- Add Task tool delegation
- Add parallel agent launching
- Add result aggregation

**Level 4 -> 5:**

- Accept PATH_TO_PROMPT variable
- Process another prompt as input
- Higher-order pattern

**Level 5 -> 6:**

- Add Specified Format template
- Meta-prompt generation workflow
- Documentation fetching

**Level 6 -> 7:**

- Add Expertise section
- Add self-improvement workflow
- Knowledge accumulation pattern

### Step 7: Save and Report

## Output

```markdown
## Prompt Upgraded

**File:** [path]
**From Level:** [N] ([name])
**To Level:** [M] ([name])

### Changes Made

**Sections Added:**
- [section 1]
- [section 2]

**Patterns Added:**
- [pattern 1]
- [pattern 2]

### New Structure

```markdown
[Updated prompt preview]
```

### Validation

- [ ] New sections properly formatted
- [ ] Variables follow conventions
- [ ] Workflow updated for new level
- [ ] STOP conditions explicit

### Testing Recommendations

1. Test basic functionality
2. Test new level capabilities
3. Verify output format

```

## Notes

- See @seven-levels.md for level definitions
- The 80/20 rule: Levels 3-4 cover most use cases
- Don't over-engineer - upgrade only when needed
