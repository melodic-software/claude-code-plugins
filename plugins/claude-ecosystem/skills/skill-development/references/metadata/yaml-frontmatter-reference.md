# YAML Frontmatter Reference

Quick reference for querying official YAML frontmatter documentation.

## Official Documentation Query

For complete YAML frontmatter specification, query docs-management:

```text
Find documentation about YAML frontmatter using keywords: YAML frontmatter, skill metadata, frontmatter specification, required fields
```

## Common Queries

**For field requirements:**
**Query docs-management:** "Find the official field requirements for skill YAML frontmatter"

**For validation rules:**
**Query docs-management:** "Find YAML frontmatter validation requirements and constraints"

**For allowed-tools specification:**
**Query docs-management:** "Find documentation about allowed-tools configuration"

**For syntax and formatting:**
**Query docs-management:** "Find YAML frontmatter syntax requirements and common errors"

## Quick Reference (Metadata Only)

> **Note:** This is a quick summary. Query docs-management for authoritative specification.

**Valid Fields (Whitelist):**

- `name` (REQUIRED) - See docs-management for complete requirements
- `description` (REQUIRED) - See docs-management for complete requirements
- `allowed-tools` (OPTIONAL) - See docs-management for complete requirements

**NO OTHER FIELDS ARE VALID.** Any field not listed above (e.g., `version`, `location`, `author`, `tags`, `category`) is invalid.

**Critical Structure Requirements:**

- Opening `---` MUST be on line 1
- Closing `---` MUST appear before content
- Valid YAML syntax (no tabs, use 2 spaces)

**Note:** For detailed requirements, examples, validation rules, and troubleshooting, query docs-management using the patterns above.

## Common Syntax Errors

**Frequently encountered issues:**

1. **Missing opening delimiter** - File must start with `---` on line 1
2. **Using tabs instead of spaces** - YAML requires spaces for indentation
3. **Invalid field names** - Only `name`, `description`, `allowed-tools` are valid
4. **Missing closing delimiter** - Must have `---` after frontmatter
5. **Angle brackets in description** - `<` and `>` cause parsing issues
6. **Wrong case for tools** - Tool names are case-sensitive (e.g., `Read` not `read`)

**For troubleshooting guidance:**
**Query docs-management:** "Find YAML frontmatter troubleshooting and common errors"

## Validation Workflow

When validating YAML frontmatter:

1. Query docs-management for current specification
2. Verify only valid fields are present (`name`, `description`, `allowed-tools`)
3. Check field-specific requirements via docs-management queries
4. Validate syntax (opening/closing `---`, YAML format)
5. Run automated validation if available

For complete validation workflow, query docs-management: "Find skill validation workflow and YAML frontmatter checking procedures"
