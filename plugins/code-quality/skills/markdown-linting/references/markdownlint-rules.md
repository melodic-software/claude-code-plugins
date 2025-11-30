# Markdownlint Rules Reference

This document provides detailed information about commonly encountered markdownlint rules and how to configure them.

## Official Documentation

For comprehensive rule documentation, see: [markdownlint Rules](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)

## Table of Contents

- [Official Documentation](#official-documentation)
- [Example Configuration](#example-configuration)
- [Commonly Encountered Rules](#commonly-encountered-rules)
  - [MD001 - Heading levels should only increment by one level at a time](#md001---heading-levels-should-only-increment-by-one-level-at-a-time)
  - [MD004 - Unordered list style](#md004---unordered-list-style)
  - [MD007 - Unordered list indentation](#md007---unordered-list-indentation)
  - [MD009 - Trailing spaces](#md009---trailing-spaces)
  - [MD012 - Multiple consecutive blank lines](#md012---multiple-consecutive-blank-lines)
  - [MD013 - Line length](#md013---line-length)
  - [MD022 - Headings should be surrounded by blank lines](#md022---headings-should-be-surrounded-by-blank-lines)
  - [MD025 - Multiple top-level headings in the same document](#md025---multiple-top-level-headings-in-the-same-document)
  - [MD033 - Inline HTML](#md033---inline-html)
  - [MD041 - First line in file should be a top-level heading](#md041---first-line-in-file-should-be-a-top-level-heading)
  - [MD048 - Code fence style](#md048---code-fence-style)
  - [MD051 - Link fragments should be valid](#md051---link-fragments-should-be-valid)
  - [MD052 - Reference links and images should use a label that is defined](#md052---reference-links-and-images-should-use-a-label-that-is-defined)
- [Rule Categories](#rule-categories)
- [Understanding Rule Numbers](#understanding-rule-numbers)
- [Disabling Rules (Not Recommended)](#disabling-rules-not-recommended)
- [Additional Resources](#additional-resources)

## Example Configuration

Example `.markdownlint-cli2.jsonc` configuration (single source of truth in your project root):

```jsonc
{
  "gitignore": true,
  "ignores": ["vendor/**/*.md"],
  "config": {
    "default": true,
    "MD013": false
  }
}
```

This example configuration:

- Automatically excludes files from `.gitignore`
- Explicitly ignores additional patterns (e.g., vendor directory)
- Enables all default markdownlint rules
- **Disables MD013** (line-length) - allows long lines in markdown files

See the [Installation and Setup Guide](installation-setup.md) for help creating your configuration file.

## Commonly Encountered Rules

### MD001 - Heading levels should only increment by one level at a time

**Rationale:** Skipping heading levels can confuse screen readers and markdown parsers.

**Violation:**

```markdown
# Heading 1
### Heading 3 (skipped level 2)
```

**Fix:**

```markdown
# Heading 1
## Heading 2
### Heading 3
```

**Auto-fixable:** No

---

### MD004 - Unordered list style

**Rationale:** Consistent list markers improve readability.

**Violation:**

```markdown
- Item 1
* Item 2
+ Item 3
```

**Fix:**

```markdown
- Item 1
- Item 2
- Item 3
```

**Auto-fixable:** Yes

---

### MD007 - Unordered list indentation

**Rationale:** Consistent indentation improves readability.

**Default:** Lists should be indented by 2 spaces per level.

**Violation:**

```markdown
- Item 1
    - Nested item (4 spaces)
```

**Fix:**

```markdown
- Item 1
  - Nested item (2 spaces)
```

**Auto-fixable:** Yes

---

### MD009 - Trailing spaces

**Rationale:** Trailing spaces are invisible and can cause unexpected rendering.

**Violation:**

```markdown
This line has trailing spaces.
```

**Fix:**

```markdown
This line has no trailing spaces.
```

**Auto-fixable:** Yes

---

### MD012 - Multiple consecutive blank lines

**Rationale:** Excessive blank lines reduce document density without improving readability.

**Violation:**

```markdown
Paragraph 1


Paragraph 2
```

**Fix:**

```markdown
Paragraph 1

Paragraph 2
```

**Auto-fixable:** Yes

---

### MD013 - Line length

**Status:** **Commonly disabled** (as shown in example configuration)

**Rationale:** Line length limits improve readability, but can be overly restrictive for documentation with long URLs, tables, or code examples.

**Configuration:** Often disabled for documentation projects. Enable if you want to enforce line length limits.

---

### MD022 - Headings should be surrounded by blank lines

**Rationale:** Blank lines around headings improve readability and parsing.

**Violation:**

```markdown
Paragraph text.
## Heading
More text.
```

**Fix:**

```markdown
Paragraph text.

## Heading

More text.
```

**Auto-fixable:** Yes

---

### MD025 - Multiple top-level headings in the same document

**Rationale:** A document should have only one H1 heading (the title).

**Violation:**

```markdown
# First Title
Content

# Second Title
```

**Fix:**

```markdown
# Main Title

## First Section

Content

## Second Section
```

**Auto-fixable:** No

---

### MD033 - Inline HTML

**Rationale:** Markdown should be pure markdown; HTML reduces portability and can break parsers.

**Violation:**

```markdown
This is <b>bold</b> text.
```

**Fix:**

```markdown
This is **bold** text.
```

**Auto-fixable:** No

**Note:** Some HTML elements may be allowed via configuration if necessary (e.g., `<br>` for line breaks).

---

### MD041 - First line in file should be a top-level heading

**Rationale:** Documents should start with a title.

**Violation:**

```markdown
Some introductory text.

# Title
```

**Fix:**

```markdown
# Title

Some introductory text.
```

**Auto-fixable:** No

---

### MD048 - Code fence style

**Rationale:** Consistent code fence style improves readability.

**Violation:**

```markdown
~~~javascript
code
~~~
```

**Fix:**

````markdown
```javascript
code
```
````

**Auto-fixable:** Yes

---

### MD051 - Link fragments should be valid

**Rationale:** Broken anchor links reduce document usability.

**Violation:**

```markdown
[Link to section](#non-existent-section)
```

**Fix:**

```markdown
[Link to section](#existing-section)

## Existing Section
```

**Auto-fixable:** No

---

### MD052 - Reference links and images should use a label that is defined

**Rationale:** Broken reference links reduce document usability.

**Violation:**

```markdown
[Link text][undefined-ref]
```

**Fix:**

```markdown
[Link text][defined-ref]

[defined-ref]: https://example.com
```

**Auto-fixable:** No

---

## Rule Categories

### Auto-Fixable Rules

These rules can be automatically fixed using the `--fix` flag:

```bash
# With npx
npx markdownlint-cli2 "**/*.md" --fix

# With npm scripts (if configured)
npm run lint:md:fix
```

**Auto-fixable rules:**

- MD004 - Unordered list style
- MD007 - Unordered list indentation
- MD009 - Trailing spaces
- MD012 - Multiple consecutive blank lines
- MD022 - Headings should be surrounded by blank lines
- MD048 - Code fence style

### Manual Fix Required

These rules require manual correction:

- MD001 - Heading levels
- MD025 - Multiple top-level headings
- MD033 - Inline HTML
- MD041 - First line should be top-level heading
- MD051 - Link fragments
- MD052 - Reference links

## Understanding Rule Numbers

Rule numbers follow the format: **MDXXX** or **MDXXX/rule-name**

- **MD** prefix indicates "Markdown"
- **Number** is the rule identifier
- **Name** (optional) is the human-readable rule name

Example: **MD022/blanks-around-headings**

## Disabling Rules (Not Recommended)

**WARNING: Think carefully before disabling rules. They exist for good reasons (quality, accessibility, consistency).**

### Inline Comments (File-Specific)

Disable a rule for a specific line:

```markdown
<!-- markdownlint-disable MD033 -->
This line can contain <b>HTML</b>.
<!-- markdownlint-enable MD033 -->
```

Disable a rule for the entire file:

```markdown
<!-- markdownlint-disable MD033 -->

# Document Title

This entire file can contain <b>HTML</b>.
```

### Configuration File (Project-Wide)

Disable a rule for all files by modifying `.markdownlint-cli2.jsonc`:

```jsonc
{
  "gitignore": true,
  "ignores": [],
  "config": {
    "default": true,
    "MD033": false
  }
}
```

**Remember:** Always fix content first. Only disable rules if you have a compelling reason (accessibility requirements, valid use case, etc.).

## Additional Resources

- **Official Rules Documentation:** [github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md](https://github.com/DavidAnson/markdownlint/blob/main/doc/Rules.md)
- **Rule Tags and Categories:** [github.com/DavidAnson/markdownlint#tags](https://github.com/DavidAnson/markdownlint#tags)
- **Configuration Guide:** [github.com/DavidAnson/markdownlint#configuration](https://github.com/DavidAnson/markdownlint#configuration)

---

**Last Verified:** 2025-11-25
