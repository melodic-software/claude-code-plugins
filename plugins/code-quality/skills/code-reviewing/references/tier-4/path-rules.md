# Path Rules

Path convention checks enforcing CLAUDE.md path requirements. Ensures portable, maintainable paths across all content.

## Absolute Path Prohibition

- [ ] No absolute paths in documentation files
- [ ] No drive letters in examples or instructions
- [ ] No user home directory references in documentation

**Detection patterns:**

- Drive letters (Windows-specific)
- Full paths starting from root directory
- User directory references
- Platform-specific absolute paths

**Rationale:** Absolute paths break portability across machines, users, and operating systems

## Root-Relative Paths Required

- [ ] Use paths relative to repository root
- [ ] Format: `docs/git-setup.md`, `.claude/skills/foo/SKILL.md`
- [ ] Consistent forward slashes (even for Windows documentation)

**Detection:** Paths should start with known root-level directories (docs/, .claude/, etc.)

**Rationale:** Root-relative paths work across environments and are version-control friendly

## Generic Placeholders

- [ ] Use placeholders instead of explicit paths in examples
- [ ] Common placeholders: `<repo-root>`, `<skill-name>`, `<path>`, `<script>`, `<relative-path>`
- [ ] Describe patterns in natural language when possible

**Example (good):**

```markdown
Use helper scripts that handle path resolution automatically.
Run scripts using relative paths from repo root (pattern: `python .claude/skills/<skill-name>/scripts/<script>.py`).
```

**Example (bad):**

```markdown
Run: `python .claude/skills/official-docs/scripts/run_tests_safely.py`
```

**Detection:** Look for overly specific file paths in examples

**Rationale:** Generic examples are maintainable, adaptable, and less brittle

## Script Self-Location Patterns

### Python Scripts

- [ ] Use `Path(__file__).resolve()` to get script's absolute location
- [ ] Resolve target paths from script location, not relative to CWD
- [ ] Never assume current working directory

**Pattern:**

```python
from pathlib import Path

script_dir = Path(__file__).resolve().parent
repo_root = script_dir.parent.parent.parent  # Adjust as needed
target_file = repo_root / "docs" / "example.md"
```

**Detection:** Check Python scripts for path resolution logic

**Rationale:** Scripts work regardless of where they're invoked from

### PowerShell Scripts

- [ ] Use `$PSScriptRoot` to get script directory
- [ ] Resolve paths from script location
- [ ] Avoid relative paths with `cd` and `&&` (PowerShell path doubling issue)

**Pattern:**

```powershell
$scriptDir = $PSScriptRoot
$repoRoot = Split-Path $scriptDir -Parent
$targetFile = Join-Path $repoRoot "docs\example.md"
```

**Detection:** Check PowerShell scripts for `$PSScriptRoot` usage

**Rationale:** Prevents path doubling and ensures cross-environment consistency

### Bash Scripts

- [ ] Use `$(dirname "$0")` or `${BASH_SOURCE[0]}` for script location
- [ ] Resolve paths absolutely before operations

**Pattern:**

```bash
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(dirname "$(dirname "$script_dir")")"
target_file="$repo_root/docs/example.md"
```

**Detection:** Check bash scripts for path resolution

**Rationale:** Portable across different invocation methods

## Path Doubling Prevention

### Common Path Doubling Scenarios

- [ ] PowerShell `cd` with `&&` causes path segments to appear twice
- [ ] Relative paths in scripts executed from wrong directory
- [ ] Chained commands without absolute path resolution

**Detection patterns:**

- Error messages with doubled path segments (e.g., `foo/bar/foo/bar`)
- Output files appearing in unexpected locations
- Scripts failing when run from different directories

**Prevention:**

- Use absolute path resolution from repo root
- Use helper scripts with `Path(__file__).resolve()` (Python) or `$PSScriptRoot` (PowerShell)
- Avoid `cd` and `&&` in PowerShell - use separate commands or absolute paths
- When creating scripts, resolve paths absolutely before operations

**Rationale:** Path doubling causes silent failures and hard-to-debug errors

## Platform-Agnostic Path Examples

- [ ] Use forward slashes in documentation (even for Windows)
- [ ] Note platform differences only when necessary
- [ ] Provide platform-specific examples only when behavior differs

**Example (good):**

```markdown
Navigate to `.claude/skills/skill-name/` directory.
```

**Example (bad):**

```markdown
On Windows: Navigate to `.claude\skills\skill-name\`.
On macOS/Linux: Navigate to `.claude/skills/skill-name/`.
```

**Detection:** Unnecessary platform-specific path variants

**Rationale:** Forward slashes work on all platforms; reduces documentation noise

## Documentation Path Examples

### In Markdown Files

- [ ] Prefer natural language patterns over explicit paths
- [ ] Use placeholders for variable components
- [ ] Avoid showing full paths in command examples unless necessary

**Good:**

```markdown
Run the script from the repository root using relative paths.
```

**Bad:**

```markdown
Run `python .claude/skills/official-docs/scripts/management/rebuild_index.py` from repo root.
```

**Detection:** Overly specific paths in documentation

**Rationale:** Documentation remains valid as file structure evolves

### In Code Comments

- [ ] Use relative paths from file's location
- [ ] Document path relationships clearly
- [ ] Avoid absolute paths in comments

**Good:**

```python
# Load config from ../../config.yaml (relative to script)
```

**Bad:**

```python
# Load config from absolute/path/to/config.yaml
```

**Detection:** Absolute paths in code comments

**Rationale:** Comments stay accurate as repository is cloned/moved

## Path Validation Checklist

### Before Committing

- [ ] No absolute paths in any documentation
- [ ] Scripts use self-location patterns
- [ ] Examples use generic placeholders
- [ ] No platform-specific path variants unless necessary
- [ ] No path doubling vulnerabilities

### During Code Review

- [ ] Check documentation for absolute paths
- [ ] Verify scripts resolve paths correctly
- [ ] Ensure examples are portable
- [ ] Test scripts from different working directories

**Rationale:** Proactive validation prevents path issues from entering codebase

## Common Violations

**High severity:**

1. Absolute paths in documentation (breaks portability)
2. Scripts without self-location logic (breaks when run from different directories)
3. Path doubling vulnerabilities (silent failures)

**Medium severity:**

1. Overly specific paths in examples (brittle)
2. Unnecessary platform-specific path variants (noise)
3. Relative paths without documented context (ambiguous)

**Low severity:**

1. Backslashes in cross-platform documentation (works but inconsistent)
2. Missing placeholders in generic examples (minor)

## Enforcement

- [ ] Automated: `block-absolute-paths` hook prevents absolute paths in committed files
- [ ] Manual: Code review catches overly specific examples and missing self-location patterns
- [ ] Testing: Verify scripts work from different working directories

**Rationale:** Multi-layered enforcement ensures compliance
