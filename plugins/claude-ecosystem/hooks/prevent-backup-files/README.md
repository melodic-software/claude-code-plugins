# Prevent Backup Files Hook

**Purpose:** Block creation of .bak, .backup, and similar backup files for git-tracked content.

**Rationale:** Git provides comprehensive version control. Backup files are unnecessary, clutter the repository, and can lead to confusion about which version is authoritative.

## Configuration

**Config file:** `config.yaml`

**Quick toggle:**

```yaml
enabled: false  # Disable this hook
```

**Enforcement levels:**

```yaml
enforcement: block  # block, warn, or log
```

## How It Works

### Trigger

- **Event:** PreToolUse
- **Tools:** Write, Edit
- **When:** Before file write/edit operations

### Detection

1. Checks if file_path ends with backup extension
2. Backup extensions from global config:
   - `.bak`
   - `.backup`
   - `~`
   - `.orig`
   - `.swp`
   - `.swo`
   - `.tmp`

### Exclusions

- `.git/`
- `node_modules/`
- `__pycache__/`
- `.claude/temp/` (use this for temporary files)

### Response

- **Block mode (default):** Exit 2, prevents file creation
- **Warn mode:** Exit 1, shows warning but allows creation
- **Log mode:** Exit 0, logs but doesn't prevent

## Examples

### Blocked Operations

```bash
# Creating .bak file
Write: "test.bak"
→ BLOCKED: "Attempted to create backup file: test.bak"

# Editing backup file
Edit: "config.backup"
→ BLOCKED: "Attempted to create backup file: config.backup"
```

### Allowed Operations

```bash
# Regular files
Write: "README.md"
→ ALLOWED

# Temp directory (excluded)
Write: ".claude/temp/temp_analysis.bak"
→ ALLOWED (in excluded path)
```

## Configuration Options

### Disable Hook

```yaml
enabled: false
```

### Change to Warning

```yaml
enforcement: warn
```

### Add Exclusions

```yaml
patterns:
  excluded_paths:
    - 'docs/examples'
    - 'tests/fixtures'
```

### Extend Patterns

```yaml
patterns:
  additional_extensions:
    - '.temp'
    - '.old'
```

## Testing

Test hook directly:

```bash
# Should block
echo '{"tool": "Write", "file_path": "test.bak"}' | \
  .claude/hooks/prevent-backup-files/prevent-backup-files.sh
echo "Exit code: $?"  # Should be 2

# Should allow
echo '{"tool": "Write", "file_path": "README.md"}' | \
  .claude/hooks/prevent-backup-files/prevent-backup-files.sh
echo "Exit code: $?"  # Should be 0
```

## Troubleshooting

### False Positive

If legitimate file is blocked, add to exclusions in `config.yaml`

### Hook Not Running

1. Check `enabled: true` in `config.yaml`
2. Check global enabled in `.claude/hooks/config/global.yaml`
3. Verify registration in `.claude/settings.json`
4. Restart Claude Code

### Dependencies

- **jq** (JSON processor) - required
- **bash** - available via Git Bash on Windows

## Related

- **CLAUDE.md:** Line 54 (rule automated by this hook)
- **Global config:** `.claude/hooks/config/global.yaml` (shared patterns)
- **Shared utilities:** `.claude/hooks/shared/` (json, path, config helpers)

## Last Updated

2025-11-18
