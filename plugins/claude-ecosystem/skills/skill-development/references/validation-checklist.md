# Skill Validation Checklist

**Source:** Official Claude Code documentation (platform.claude.com, code.claude.com)

Use this checklist before creating or renaming skills. All rules are extracted from official documentation.

## YAML Frontmatter Requirements

### `name` Field (Required)

- [ ] **Maximum 64 characters**
- [ ] **Lowercase letters, numbers, and hyphens only** (no uppercase, no spaces)
- [ ] **No XML tags** in the name
- [ ] **No reserved words:** Cannot contain "anthropic" or "claude"
- [ ] **Non-empty**

**Valid examples:**
- `processing-pdfs`
- `analyzing-spreadsheets`
- `managing-databases`
- `skill-development`

**Invalid examples:**
- `Processing-PDFs` (uppercase letters)
- `claude-helper` (reserved word "claude")
- `anthropic-docs` (reserved word "anthropic")
- `my skill name` (spaces)
- `helper` (too vague per best practices)

### `description` Field (Required)

- [ ] **Non-empty**
- [ ] **Maximum 1024 characters**
- [ ] **No XML tags**
- [ ] **Written in third person** (not "I can help" or "You can use")
- [ ] **Describes what the Skill does AND when to use it**
- [ ] **Includes specific triggers/contexts**

**Good example:**
```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

**Bad examples:**
```yaml
description: Helps with documents  # Too vague
description: I can process PDFs for you  # First person
description: You can use this to extract text  # Second person
```

## Naming Convention Consistency

Per official documentation:

- [ ] **Gerund form recommended:** `processing-pdfs`, `analyzing-data`
- [ ] **Noun phrases acceptable:** `pdf-processing`, `data-analysis`
- [ ] **Action-oriented acceptable:** `process-pdfs`, `analyze-data`
- [ ] **Consistent within plugin:** All skills in same plugin use same pattern

**This plugin uses:** Noun-phrase pattern (e.g., `skill-development`, `docs-management`)

## SKILL.md Structure

- [ ] **Starts with YAML frontmatter** (between `---` delimiters)
- [ ] **Body under 500 lines** for optimal performance
- [ ] **Progressive disclosure** - reference files for detailed content
- [ ] **References one level deep** - no nested references

## Pre-Creation Verification

Before creating a new skill:

1. [ ] Check name is unique within the plugin
2. [ ] Verify name follows naming pattern used by other skills in plugin
3. [ ] Confirm no reserved words in name
4. [ ] Description is specific enough for Claude to select correctly
5. [ ] Description includes both "what" and "when"

## Common Mistakes to Avoid

- Using "anthropic" or "claude" in skill names
- Inconsistent naming patterns within a plugin
- Vague descriptions that don't help with skill selection
- First/second person in descriptions
- Deeply nested reference files
- SKILL.md files over 500 lines

---

**Last Updated:** 2025-11-30
**Source References:**
- `platform-claude-com/docs/en/agents-and-tools/agent-skills/best-practices.md`
- `code-claude-com/docs/en/skills.md`
