# Creating Skills Workflow

Step-by-step workflow for creating new Claude Code skills with delegation to official documentation.

## Official Documentation Query

For complete skill creation guidance, query official-docs:

```text
Find documentation about creating skills using keywords: creating skills, skill structure, YAML frontmatter, skill best practices
```

## Workflow Overview

**High-Level Steps:**

1. **Choose Template** → Select structural pattern
2. **Query Official Docs** → Load creation guidance
3. **Create Skill Files** → Setup directory and SKILL.md
4. **Write YAML Frontmatter** → Complete name and description
5. **Write Skill Body** → Add content following chosen pattern
6. **Add Supporting Files** → Scripts, references, assets as needed
7. **Test Activation** → Verify skill loads correctly
8. **Validate Quality** → Check against official requirements

## Detailed Workflow

### Step 1: Choose Template

Query official-docs: "Find skill structural patterns and template guidance"

**Decision**: Choose ONE of:

- Workflow-Based
- Task-Based
- Reference-Based
- Capabilities-Based
- Validation Feedback Loop

### Step 2: Query Official Documentation

Query official-docs with appropriate keywords:

- "Find skill creation requirements and best practices"
- "Find YAML frontmatter specification"
- "Find progressive disclosure patterns"

### Step 3: Create Skill Directory

```bash
mkdir -p .claude/skills/[skill-name]
cd .claude/skills/[skill-name]
```

For detailed setup, query official-docs: "Find skill directory structure and organization"

### Step 4: Write YAML Frontmatter

Query official-docs: "Find YAML frontmatter field requirements"

**Required Fields:**

- `name`: Skill identifier (see naming-conventions.md)
- `description`: What it does and when to use it

**Optional Fields:**

- `allowed-tools`: Tool access restrictions

### Step 5: Write Skill Body

Query official-docs: "Find skill body structure and content best practices"

**Include:**

- Overview
- When to use this skill
- Examples with input/output pairs
- Concrete, not abstract examples

### Step 6: Add Supporting Files

If needed:

- `references/` - Detailed documentation (progressive disclosure)
- `scripts/` - Automation scripts
- `assets/` - Templates, examples, data files

Query official-docs: "Find progressive disclosure and supporting files guidance"

### Step 7: Test Activation

Query official-docs: "Find skill activation testing procedures"

**Test with varied phrasings:**

1. Direct: "Use the [skill-name] skill to..."
2. Domain: "Help me with [domain]..."
3. Task: "I need to [task]..."

### Step 8: Validate Quality

Query official-docs: "Find skill validation requirements and quality standards"

**Validate:**

- YAML syntax correct
- Naming conventions followed
- Description includes triggers
- Examples are concrete
- Activation works

For comprehensive validation, use the validation workflow (see validating-skills-workflow.md)

## Common Queries for Each Step

**For template selection:**
**Query official-docs:** "Find skill structural patterns and when to use each"

**For naming:**
**Query official-docs:** "Find skill naming conventions and The Sentence Test"

**For description writing:**
**Query official-docs:** "Find skill description best practices and trigger keywords"

**For progressive disclosure:**
**Query official-docs:** "Find progressive disclosure implementation patterns"

**For activation testing:**
**Query official-docs:** "Find skill activation troubleshooting and testing strategies"

## Decision Points

**Template selection**: Query official-docs with "Find skill structural pattern comparison"

**Progressive disclosure**: If skill exceeds size threshold, query "Find progressive disclosure implementation" (see SKILL.md#specifications-quick-reference for current thresholds)

**Tool restrictions**: If read-only needed, query "Find allowed-tools configuration"

**Supporting files**: Query "Find skill organization and file structure best practices"

For all implementation details, query official-docs with the patterns above.
