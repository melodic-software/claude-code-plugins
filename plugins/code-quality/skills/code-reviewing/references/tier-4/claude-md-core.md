# CLAUDE.md Core Rules

Quick reference for most common CLAUDE.md violations. Always checked when CLAUDE.md exists in repository.

## Path Rules

- [ ] No absolute paths in documentation (drive letters, user home directories, etc.)
- [ ] Use root-relative paths (`docs/git-setup.md`, `.claude/skills/foo/`)
- [ ] Use generic placeholders for examples (`<repo-root>`, `<skill-name>`, `<path>`)

**Detection:** Look for drive letters, home directory markers, or fully qualified paths

**Rationale:** Absolute paths break portability across machines/users and create brittle documentation

## Title-Filename Consistency

- [ ] Markdown `# header` matches filename (kebab-case → Title Case with spaces)
- [ ] Example: `git-setup-windows.md` → `# Git Setup Windows`
- [ ] Exception: Root meta files (README.md, CLAUDE.md) may use descriptive titles
- [ ] Exception: Platform-agnostic content may omit platform suffix in title

**Detection:** Extract `# header` from first line, compare to filename after case conversion

**Rationale:** Predictable navigation and AI-friendly structure

## Platform Content Separation

- [ ] No mixed platform content in single file (no "On Windows... On macOS..." sections)
- [ ] Create separate files: `tool-name-windows.md`, `tool-name-macos.md`, `tool-name-linux.md`
- [ ] Or: Shared content + platform supplements if 80%+ identical

**Detection:** Search for "On Windows", "On macOS", "On Linux", "For Windows users", "Mac users should"

**Rationale:** Separation of concerns - each file serves exactly one platform

## File Organization

- [ ] No README.md files in topic folders (only at repository root)
- [ ] Hub files only at root and `docs/{platform}-onboarding.md`
- [ ] Topic folders contain only topic-specific content

**Detection:** Find README.md files in subdirectories

**Rationale:** Prevents documentation sprawl and maintains clear navigation hierarchy

## Naming Conventions

- [ ] No numbered filename prefixes (`01-git-setup.md`, `02-nodejs.md`)
- [ ] Ordering controlled by hub documents, not filenames
- [ ] Allows reordering without mass renames

**Detection:** Filenames starting with digits followed by dash/underscore

**Rationale:** Flexibility in reordering without brittle numbering schemes

## Encoding and Punctuation

- [ ] UTF-8 encoding for all files (emojis allowed and encouraged)
- [ ] ASCII punctuation only: straight quotes (`"`, `'`), standard dashes (`-`, `--`)
- [ ] No smart quotes, curly quotes, or Unicode punctuation substitutes

**Detection:** Search for `"`, `"`, `'`, `'`, `—`, `–`, `…`

**Rationale:** Consistency across platforms and editors; UTF-8 supports emojis natively

## Single Source of Truth

- [ ] No duplicated content across files
- [ ] Version info in ONE "Last Verified" section (typically SKILL.md)
- [ ] Hub files link to detailed content (no copy-paste)
- [ ] Configuration examples exist in ONE canonical location

**Detection:** Compare content across files, search for repeated version numbers, duplicate code blocks

**Rationale:** DRY principle - update once, reference everywhere else

## Quick Violations Summary

**Most common issues:**

1. Absolute paths in documentation (high severity)
2. Duplicate content across files (high severity)
3. Mixed platform content in single file (medium severity)
4. Title-filename mismatch (medium severity)
5. Smart quotes instead of ASCII (low severity)
6. Numbered filenames (low severity)

**Fix priority:** Address absolute paths and duplication first - these cause the most maintenance burden.
