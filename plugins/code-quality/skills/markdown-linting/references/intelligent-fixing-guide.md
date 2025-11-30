# Intelligent Fixing Guide

This guide provides detailed strategies for handling "unfixable" markdown linting errors that require context-aware analysis and manual fixes.

## Overview

After running auto-fix (`--fix` flag), some errors remain that cannot be automatically corrected. These require intelligent analysis of the file content and context to apply appropriate fixes.

**Workflow:**

1. Run auto-fix first: `npx markdownlint-cli2 "**/*.md" --fix`
2. For remaining errors, read the affected file to understand context
3. Analyze the error and surrounding content
4. Apply intelligent fixes based on patterns below
5. Re-run linting to verify all errors are resolved

## MD024 - Duplicate Headings

**When detected:**

1. Read the file containing the duplicate heading
2. Find all instances of the duplicate heading
3. Analyze context around each instance:
   - What section is it in?
   - What content follows?
   - Is one redundant or serving a different purpose?
4. Apply fix:
   - **If redundant**: Remove the duplicate section or merge it with the first instance
   - **If different contexts**: Rename one to be more specific based on surrounding content (e.g., add context like "- Script Usage", "- Reminder", "- Troubleshooting")
5. Re-run linting to verify the fix

**Example:**

- First instance: `## CRITICAL: Large File Handling` (at top, general warning)
- Second instance: `## CRITICAL: Large File Handling` (later in file, redundant)
- Fix: Remove second instance OR rename to `## CRITICAL: Large File Handling - Reminder`

## MD001/MD025 - Heading Structure

**When detected:**

1. Read the file to understand the heading hierarchy
2. Analyze the structure:
   - Are headings properly nested?
   - Is there a skipped level (e.g., h1 -> h3)?
   - Are multiple h1 headings present (MD025)?
3. Apply fix:
   - Adjust heading levels to maintain proper hierarchy
   - If multiple h1 headings, convert subsequent ones to h2 (or appropriate level)
   - Ensure no skipped levels

## MD051/MD052 - Link References

**When detected:**

1. Read the file to find broken links
2. Analyze link targets:
   - Is the target file/section nearby?
   - Can the link be corrected based on context?
   - Is it a reference link that needs a definition?
3. Apply fix:
   - Correct anchor links if the target heading exists
   - Add missing reference link definitions
   - Fix file paths if the target file is clear from context
   - If target is unclear, leave as-is (don't guess)

## MD013 - Line Length (if enabled)

**When detected:**

1. Read the file to see long lines
2. Analyze content:
   - Is it a code block or inline code? (may be acceptable)
   - Is it a URL or long path? (may be acceptable)
   - Is it regular text that can be wrapped?
3. Apply fix:
   - Wrap long text lines appropriately
   - Preserve code blocks and URLs
   - Maintain readability

## General Principles

### Context-Aware Analysis

- **Always read the full file** to understand the content structure
- **Consider surrounding content** when deciding how to fix errors
- **Preserve intent** - don't change meaning while fixing format
- **Maintain consistency** - use similar patterns throughout the file

### Verification

- **Always re-run linting** after applying fixes to confirm all errors are resolved
- **Check for new errors** that might be introduced by fixes
- **Test links** if you modified them to ensure they work

### Reporting

- **Document what was fixed** - explain the changes clearly
- **Explain why** - provide rationale for non-obvious fixes
- **Note any limitations** - if some errors couldn't be fixed, explain why

## Advanced Scenarios

### Multiple Error Types in One File

When a file has multiple different error types:

1. Group errors by type (MD024, MD001, MD051, etc.)
2. Fix errors in order of dependency (structure first, then content)
3. Re-run linting after each major change
4. Verify no new errors were introduced

### Complex Heading Hierarchies

For files with deep or complex heading structures:

1. Map out the full heading tree
2. Identify where hierarchy breaks occur
3. Fix from top-down (h1 -> h2 -> h3, etc.)
4. Ensure logical nesting (content under correct parent)

### Ambiguous Link Targets

When link targets are unclear:

1. Search for likely target files in the repository
2. Check if similar links exist elsewhere in the file
3. If target is genuinely unclear, report to user
4. Never guess - incorrect links are worse than no links

## Performance Optimization

### Parallel Fixing with Task Agents

For large repositories with many files containing errors:

- **High-error files (20+ errors)**: Launch one agent per file
- **Medium-error files (10-20 errors)**: Launch one agent per file
- **Low-error files (1-9 errors)**: Group into batches, one agent per file

Each Task agent should:

1. Run linter to identify specific errors in their assigned file
2. Read the file to understand context
3. Use Edit tool to fix ALL errors manually (no scripts)
4. Re-run linter to verify all errors are fixed
5. Report summary of fixes applied

## Tools and Commands

### Linting Commands

```bash
# Check for errors
npx markdownlint-cli2 "**/*.md"

# Auto-fix fixable errors
npx markdownlint-cli2 "**/*.md" --fix

# Check specific file
npx markdownlint-cli2 "path/to/file.md"
```

### File Editing

- Use Edit tool for precise changes
- Never use scripts for linting fixes (manual editing required)
- Test changes by re-running linter

## Summary

Intelligent fixing requires:

1. **Context awareness** - Read and understand the file
2. **Pattern recognition** - Identify error types and apply appropriate fixes
3. **Verification** - Always re-run linting after fixes
4. **Documentation** - Report what was fixed and why

By following these patterns, you can efficiently resolve all markdown linting errors, even those that aren't auto-fixable.

---

**Last Verified:** 2025-11-25
