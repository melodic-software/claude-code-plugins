# Path Conventions

This document covers path resolution principles, script execution path handling, and documentation path standards.

## Language-Agnostic Path Resolution Principles

**Core Principles** (applies to all languages):

1. **Single Source of Truth for Paths**
   - Centralize path resolution utilities in one canonical location
   - Never duplicate path resolution logic across files
   - Import and reuse path utilities instead of recalculating
   - Example: `common_paths.py`, `path_helpers.ts`, `PathUtils.cs`

2. **Absolute Resolution from Known Anchors**
   - Use `__file__` (Python), `$PSScriptRoot` (PowerShell), `__dirname` (Node.js), `Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)` (.NET) as starting points
   - Resolve to absolute paths immediately, then navigate from there
   - Never rely on current working directory for path resolution
   - Known anchors: script file location, repo root marker (.git), config file location

3. **Depth-Independent Logic**
   - Path utilities should work regardless of caller's depth in directory tree
   - Don't hardcode assumptions about directory structure depth
   - Use semantic markers (SKILL.md, .git, package.json) to find directories
   - Walk up directory tree to find markers, don't assume fixed depth

4. **Never Hardcode Parent Chains**
   - Avoid `.parent.parent.parent` or `../../..` in business logic
   - Use semantic helper functions: `get_skill_dir()`, `get_repo_root()`, `find_project_root()`
   - If parent traversal is needed, encapsulate it in a utility function
   - Brittle: `Path(__file__).parent.parent.parent` - breaks when files move
   - Robust: `get_skill_dir(from_path=Path(__file__))` - adapts to structure

5. **Minimal Bootstrap Acceptable**
   - Executable scripts need minimal path setup to import utilities (unavoidable)
   - Keep bootstrap to 2-4 lines maximum
   - Bootstrap should only setup import paths, not contain complex logic
   - All complex path resolution belongs in centralized utilities
   - Example acceptable bootstrap: `sys.path.insert(0, str(Path(__file__).resolve().parents[1]))`

6. **Test Path Utilities in Isolation**
   - Ensure path helpers work when called from any working directory
   - Test that utilities don't break when directory structure changes
   - Verify path resolution is consistent across platforms (Windows/Mac/Linux)
   - Path utilities are foundational - they must be rock-solid

## Script Execution Path Handling

**CRITICAL:** When executing scripts (especially Python scripts in skills), always run from the repository root:

- **Use relative paths from repo root**: Use relative paths from repo root when you're certain you're at repo root (pattern: `python .claude/skills/<skill-name>/scripts/<script>.py`)
- **Prefer helper scripts**: Use helper scripts that internally resolve their own location using `Path(__file__).resolve()` - these work from any directory
- **If ensuring directory**: Change to repo root first, then run script separately (never chain with `&&`)
- **Never chain `cd` commands**: `cd <relative-path> && python <script>` causes path doubling if shell is already in a subdirectory
- **Prefer direct execution**: Run scripts with full relative paths from repo root rather than changing directories
- **Use absolute path resolution**: If unsure of current directory, resolve paths absolutely first using `Get-Item` (PowerShell) or `Path.resolve()` (Python)

This prevents path resolution errors where the shell tries to navigate to non-existent nested paths.

## Path Doubling Prevention (CRITICAL)

**Problem:** Path doubling occurs when relative paths are resolved relative to the current working directory instead of the repository root, causing errors like `.claude\skills\official-docs\.claude\skills\official-docs` (path segment appears twice).

**Root Causes:**

1. Using `cd <relative-path> && <command>` in PowerShell when already in a subdirectory
2. Using relative paths in scripts without resolving from script location
3. Resolving paths relative to current working directory instead of script location or repo root

**Detection Patterns:**

- Error messages containing doubled path segments (e.g., `.claude\skills\official-docs\.claude\skills\official-docs`)
- File operations failing with "path does not exist" when path looks correct
- Output files appearing in unexpected nested directories
- Commands failing with "Cannot find path" errors showing doubled segments

**Prevention Strategies:**

1. **In Scripts (Python):**
   - ALWAYS use `Path(__file__).resolve()` to get absolute script location
   - Never rely on current working directory for path resolution
   - Resolve all target paths absolutely from script location or repo root
   - Example pattern: Get script file path, resolve to absolute, then navigate relative to that

2. **In Scripts (PowerShell):**
   - ALWAYS use `$PSScriptRoot` or find repo root absolutely
   - Never rely on current working directory
   - Resolve all paths absolutely before operations
   - Example pattern: Use `$PSScriptRoot` if available, otherwise resolve from script location, then find repo root by walking up directory tree until `.git` is found

3. **In Commands (PowerShell):**
   - Never chain `cd` with `&&` when using relative paths
   - Use absolute path resolution: Get absolute path first using `Get-Item` or `Resolve-Path`, store in variable, then execute
   - Use separate commands: Change directory first, then run script separately
   - Prefer helper scripts that handle path resolution automatically

4. **In Commands (Bash/Unix):**
   - Be cautious with `cd` and `&&` - can cause path doubling if already in subdirectory
   - Use absolute paths or ensure you're at repo root before using relative paths
   - Prefer helper scripts that handle path resolution automatically
   - Use `git rev-parse --show-toplevel` to find repo root absolutely if needed

**Proactive Detection:**

- When you see any path-related error, immediately check for doubled segments
- When file operations fail, verify the resolved path matches expected location
- When creating new scripts, always use absolute path resolution from script location
- When output files appear in wrong locations, check for path doubling issues

**Fix Procedure:**

1. Identify the doubled path segment in the error message
2. Determine the correct base path (repo root or script location)
3. Rewrite the command/script to resolve paths absolutely from the base
4. Verify the fix by checking resolved paths match expected locations
5. Update documentation if this was a common pattern

**Output File Location Verification:**

- After file operations, verify files are in expected locations
- If files appear in nested directories unexpectedly, check for path doubling
- Use absolute path resolution to ensure consistent file placement

## Root-Relative Paths in Documentation

All documentation MUST use root-relative paths or placeholders. NEVER hardcode absolute paths specific to a particular machine or user.

**Good Practices:**

- Relative paths: `.gitignore`, `docs/windows-onboarding.md`
- Root-relative: `<project-root>/.markdownlint-cli2.jsonc`
- User home: `~/.gitconfig`, `~/.ssh/config`
- Generic placeholders: `<drive>:\Users\<username>\`, `<home>/<username>/`

**Bad Practices:**

- Machine-specific absolute paths with actual drive letters and repo names
- Paths containing specific usernames
- Full paths that only work on one developer's machine

## Exception: Platform-Specific Teaching Examples

When teaching concepts (like file paths on different OSes), use generic placeholder patterns:

- **Windows:** `<drive>:\Users\<username>\AppData\Local\`
- **Linux:** `<home>/<username>/.config/`
- **macOS:** `<home>/<username>/Library/`

These are TEMPLATES showing users where files live on their systems, not actual repository paths.

## Repository-Agnostic Documentation

Documentation should work regardless of:

- Where the repository is cloned (any drive, any parent directory)
- What the user's username is
- What drive letter is used (Windows)
- What the parent directory structure looks like

**Rationale:**

- **Portability:** Documentation works for all users
- **Maintainability:** No need to update paths when repo moves
- **Professionalism:** Shows environment-agnostic design
- **Clarity:** Focuses on concepts, not specific machine details

---

**Last Updated:** 2025-11-30
