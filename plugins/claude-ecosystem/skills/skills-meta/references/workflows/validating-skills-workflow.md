# Validating Skills Workflow

Step-by-step workflow for validating skill quality and compliance.

## Official Documentation Query

For complete validation guidance, query official-docs:

```text
Find documentation about skill validation using keywords: skill validation, validation requirements, quality standards
```

## Workflow Overview

**High-Level Steps:**

1. **YAML Frontmatter Validation** → Check syntax and fields
2. **Naming Convention Validation** → Verify name follows rules
3. **Description Quality Validation** → Check trigger keywords
4. **Structure Validation** → Verify file organization
5. **Activation Testing** → Test skill loads correctly
6. **Quality Standards Check** → Validate against official requirements

## Detailed Workflow

### Step 1: YAML Frontmatter Validation

Query official-docs: "Find YAML frontmatter validation requirements"

**Check:**

- Opening `---` on line 1
- Closing `---` before content
- Valid YAML syntax (no tabs)
- Only valid fields (`name`, `description`, `allowed-tools`)

### Step 2: Naming Convention Validation

Query official-docs: "Find skill naming conventions and validation rules"

**Validate:**

- The Sentence Test passes
- Lowercase, hyphens only
- Within official character limit (query official-docs for current limits)
- Matches directory name
- No reserved words (query official-docs for current list)

### Step 3: Description Quality Validation

Query official-docs: "Find description best practices and trigger keywords"

**Check:**

- Third person voice
- Includes what skill does
- Includes when to use it
- Contains trigger keywords (domains, tasks, tools, file types)
- Within official character limit (query official-docs for current limits)

### Step 4: Structure Validation

Query official-docs: "Find skill structure requirements"

**Verify:**

- SKILL.md exists
- Directory name matches `name` field
- File references exist
- Progressive disclosure if exceeds size threshold (see SKILL.md#specifications-quick-reference)

### Step 5: Activation Testing

Query official-docs: "Find skill activation testing procedures"

**Test:**

1. Direct: "Use [skill-name] skill"
2. Domain: "[domain from description]"
3. Task: "[task from description]"

### Step 6: Quality Standards Check

Query official-docs: "Find skill quality standards and best practices"

**Validate:**

- Examples are concrete
- No time-sensitive info
- Consistent terminology
- Token efficient

For comprehensive validation, use the validation script if available.

## Common Queries

**For YAML syntax:**
**Query official-docs:** "Find YAML frontmatter syntax requirements and common errors"

**For naming:**
**Query official-docs:** "Find skill naming validation and The Sentence Test"

**For description:**
**Query official-docs:** "Find description best practices and trigger keyword guidance"

**For activation:**
**Query official-docs:** "Find skill activation troubleshooting"

For all validation details, query official-docs with the patterns above.
