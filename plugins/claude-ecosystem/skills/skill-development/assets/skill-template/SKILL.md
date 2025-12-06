---
name: skill-name
description: TODO: [What it does]. Use when [specific triggers]. Example: "Analyzes Excel spreadsheets and generates charts. Use when working with Excel files, .xlsx, spreadsheet analysis, or data visualization." REQUIRED: Include "Use when..." with trigger keywords (file types, domains, tasks). Third person. Max 1024 chars.
---

# Skill Name

> **NOTE**: This is a template file. After copying this directory to create a new skill, customize the YAML frontmatter and replace all TODO sections with your skill's content.

TODO: Brief 1-2 sentence overview. **Be concise** - the context window is shared with conversation history, other skills, and user requests.

## Overview

TODO: Detailed introduction explaining the purpose and scope of this skill (1 paragraph).

## When to Use This Skill

This skill should be used when:

- TODO: List specific scenarios when this skill should activate
- TODO: Include file types, operations, or keywords that should trigger activation
- TODO: Be as specific as possible to help Claude discover when to use this

## Quick Start

TODO: Provide the fastest path to value. Show the most common use case with a brief example.

Example:

```bash
# TODO: Replace with actual quick start command or code snippet
echo "Hello, world!"
```

## [Main Instructions Section]

TODO: Choose and implement ONE of these structural patterns based on your skill's purpose:

### Option 1: Workflow-Based Pattern (for sequential processes)

**Use when:** Multi-step processes, sequential operations, guided workflows

**Pattern structure:**

```markdown
## Workflow Decision Tree
## Step 1: Initial Setup
## Step 2: Configuration
## Step 3: Execution
## Troubleshooting
```

**For complex workflows, provide a checklist:**

````markdown
## PDF Form Filling Workflow

Copy this checklist and check off items as you complete them:

```
Task Progress:
- [ ] Step 1: Analyze the form
- [ ] Step 2: Create field mapping
- [ ] Step 3: Validate mapping
- [ ] Step 4: Fill the form
- [ ] Step 5: Verify output
```

**Step 1: Analyze the form**
[Instructions for this step]

**Step 2: Create field mapping**
[Instructions for this step]

[Continue for each step...]
````

### Option 2: Task-Based Pattern (for collections of operations)

**Use when:** Tool collections, utility skills, multiple independent capabilities

**Pattern structure:**

```markdown
## Task Category 1: [Name]
### Task 1.1: [Operation]
### Task 1.2: [Operation]
## Task Category 2: [Name]
### Task 2.1: [Operation]
```

### Option 3: Reference-Based Pattern (for guidelines/standards)

**Use when:** Style guides, coding standards, brand guidelines, API specifications

**Pattern structure:**

```markdown
## Core Principles
## Guidelines
## Specifications
## Usage Examples
```

### Option 4: Capabilities-Based Pattern (for integrated features)

**Use when:** Complex systems, integrated tools, multi-capability skills

**Pattern structure:**

```markdown
## Core Capabilities
## Capability 1: [Feature Name]
## Capability 2: [Feature Name]
## Integration Guide
```

### Option 5: Validation Feedback Loop Pattern (for operations requiring correctness)

**Use when:** Complex operations, batch updates, operations where errors are costly

**Pattern structure:**

````markdown
## Workflow with Validation

### Step 1: Analyze Input
[Understand requirements]

### Step 2: Generate Plan
Create intermediate plan file (e.g., changes.json)

### Step 3: Validate Plan

```bash
python scripts/validate_plan.py plan.json
```

### Step 4: Review Errors
If errors found, fix and return to Step 3

### Step 5: Execute Plan
Apply validated plan

### Step 6: Verify Output
Confirm output meets requirements
````

**Key principle:** Catch errors early through intermediate validation before expensive operations.

## Examples

TODO: Provide concrete, representative examples with input/output pairs. Examples help Claude understand desired style and level of detail better than descriptions alone.

### Example 1: Basic Usage

TODO: Show a simple, common use case. Use input/output format:

```text
Input: [What the user provides]
Expected Output:
[Show exactly what should be produced]
```

**Format guidance:** Show concrete input → output pairs. For instance, if this skill generates commit messages, show:

- Input: "Create a commit message for these changes: Added user authentication"
- Output: "feat(auth): implement user authentication system\n\nAdd login endpoints and session management"

### Example 2: Advanced Usage

TODO: Show a more complex or powerful use case using the same input/output format:

```text
Input: [More complex scenario]
Expected Output:
[Show the complete output with all details]
```

**Pattern tip:** Use input/output pairs like in regular prompting to show Claude the desired format and quality level. This works better than descriptions alone.

## Resources

This skill includes example resource directories that demonstrate how to organize different types of bundled resources:

### scripts/

Executable code (Python/Bash/etc.) that can be run directly to perform specific operations.

**Examples from other skills:**

- PDF skill: `fill_fillable_fields.py`, `extract_form_field_info.py` - utilities for PDF manipulation
- DOCX skill: `document.py`, `utilities.py` - Python modules for document processing

**Appropriate for:** Python scripts, shell scripts, or any executable code that performs automation, data processing, or specific operations.

**Note:** Scripts may be executed without loading into context, but can still be read by Claude for patching or environment adjustments.

TODO: If your skill includes scripts, list them here:

- `scripts/example.py` - TODO: Describe what this script does

### references/

Documentation and reference material intended to be loaded into context to inform Claude's process and thinking.

**Examples from other skills:**

- Product management: `communication.md`, `context_building.md` - detailed workflow guides
- BigQuery: API reference documentation and query examples
- Finance: Schema documentation, company policies

**Appropriate for:** In-depth documentation, API references, database schemas, comprehensive guides, or any detailed information that Claude should reference while working.

**IMPORTANT:** Keep references **one level deep** from SKILL.md - don't nest references beyond one level. Claude reads complete files when directly referenced from SKILL.md, but may only preview nested references.

**For large reference files (>100 lines):** Include a table of contents at the top so Claude understands available information during partial reads.

TODO: If your skill includes reference documentation, list it here:

- See [references/example.md](references/example.md) for TODO: detailed information on X

**Make content greppable:**

````markdown
To find OAuth implementation details:
```bash
grep -i "oauth" references/authentication.md
```
````

### assets/

Files not intended to be loaded into context, but rather used within the output Claude produces.

**Examples from other skills:**

- Brand styling: PowerPoint template files (.pptx), logo files
- Frontend builder: HTML/React boilerplate project directories
- Typography: Font files (.ttf, .woff2)

**Appropriate for:** Templates, boilerplate code, document templates, images, icons, fonts, or any files meant to be copied or used in the final output.

TODO: If your skill includes assets, list them here:

- `assets/example.txt` - TODO: Describe what this asset is for

---

**Any unneeded directories can be deleted.** Not every skill requires all three types of resources.

## Troubleshooting

TODO: Document common issues and solutions:

**Issue: [Common Problem]**

- **Cause**: TODO: Why this happens
- **Solution**: TODO: How to fix it

**Issue: [Another Common Problem]**

- **Cause**: TODO: Why this happens
- **Solution**: TODO: How to fix it

## Best Practices

TODO: List recommendations for using this skill effectively:

- TODO: Best practice 1
- TODO: Best practice 2
- TODO: Best practice 3

## Version History

- v1.0.0 (YYYY-MM-DD): Initial release

---

## Template Usage Instructions

**Before deploying this skill, complete all TODO items:**

1. ✅ Replace `skill-name` in frontmatter with actual name (lowercase, hyphens, max 64 chars)
2. ✅ Write specific `description` with both functionality AND trigger scenarios (max 1024 chars)
3. ✅ Replace all TODO sections with actual content
4. ✅ Choose and implement ONE structural pattern (remove others)
5. ✅ Add concrete examples relevant to your skill
6. ✅ Document any supporting files (scripts, references, assets)
7. ✅ Remove this "Template Usage Instructions" section
8. ✅ Validate YAML frontmatter syntax
9. ✅ Test skill activation with representative queries
10. ✅ Ensure directory name matches `name` field exactly

**Structural Pattern Selection:**

- **Workflow-Based**: Sequential processes with clear steps (e.g., setup workflows, multi-step operations)
- **Task-Based**: Collections of related operations (e.g., PDF tools, API operations)
- **Reference-Based**: Standards and guidelines (e.g., brand guidelines, coding standards)
- **Capabilities-Based**: Integrated feature sets (e.g., platform capabilities, product features)

**Content Sizing:**

- **Official guidance**: Keep under 500 lines or 5k tokens for optimal performance
- **Target**: 2,000-5,000 words in SKILL.md
- **Maximum**: ~10,000 words - if exceeding, use references/ for details
- **Minimum**: ~500 words - provide sufficient context
- Move detailed documentation to references/ if approaching limits
- Keep this file focused on essential instructions

### Writing Principle: "Concise is Key"

The context window is shared with conversation history, other skills, and user requests.

- Challenge each explanation: "Does Claude really need this?"
- Omit what Claude already knows (what PDFs are, what libraries do)
- Focus on your domain specifics, requirements, and workflows
- Example: Don't explain what OAuth is; explain YOUR OAuth configuration

**Set Appropriate Degrees of Freedom:**

Match specificity to task fragility:

- **High freedom** (text instructions): Multiple valid approaches, context-dependent decisions
- **Medium freedom** (pseudocode/templates): Preferred pattern with acceptable variation
- **Low freedom** (exact scripts): Fragile operations, consistency critical, specific sequence required

**Description Tips:**

**CRITICAL: Always use third person** - Description is injected into system prompt:

- ✅ "Processes Excel files and generates reports"
- ❌ "I can help you process Excel files" (first person)
- ❌ "You can use this to process Excel files" (second person)

Include these keyword types:

- File types: `.md`, `.json`, `.xlsx`, `PDF`, `Excel`
- Domains: `API`, `authentication`, `database`, `testing`
- Tasks: `analyze`, `generate`, `create`, `build`, `validate`
- Tools: `Git`, `Docker`, `Kubernetes`, `PostgreSQL`

**Official Pattern:** `[What it does]. Use when [specific triggers].`

This is the ONLY documented mechanism for skill discovery. Claude uses descriptions to choose skills from 100+ available. Include BOTH capabilities AND triggers.

**Example descriptions:**

✅ Excellent (follows official pattern):

```yaml
description: Analyzes Excel spreadsheets, generates pivot tables, creates charts. Use when working with Excel files (.xlsx, .xls), spreadsheet analysis, or data visualization tasks.
```

✅ Good (clear triggers):

```yaml
description: Generates descriptive commit messages by analyzing git diffs. Use when writing commit messages, reviewing staged changes, or preparing git commits.
```

❌ Missing "Use when..." triggers:

```yaml
description: Generates descriptive commit messages.
```

❌ Too vague:

```yaml
description: Helps with files.
```

❌ Wrong voice (must be third person):

```yaml
description: I will help you analyze spreadsheets.
```

**Validation Checklist:**

- [ ] YAML frontmatter is valid
- [ ] `name` follows conventions (lowercase, hyphens, max 64 chars)
- [ ] `name` matches directory name exactly
- [ ] `description` follows official pattern: `[What it does]. Use when [triggers].`
- [ ] `description` includes "Use when..." with specific trigger keywords
- [ ] All TODO items are replaced
- [ ] Examples are concrete and representative
- [ ] Supporting files are documented (if present)
- [ ] Skill activates for expected scenarios
