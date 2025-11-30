# Common Issues and Solutions

**Last Updated:** 2025-11-25

## Overview

Common hook issues and their solutions, organized by symptom.

## Table of Contents

- [Hook Not Running](#hook-not-running)
- [Config Changes Not Taking Effect](#config-changes-not-taking-effect)
- [Hook Errors](#hook-errors)
- [False Positives](#false-positives)
- [False Negatives](#false-negatives)
- [Performance Issues](#performance-issues)
- [Debugging Workflow](#debugging-workflow)
- [Getting Help](#getting-help)

## Hook Not Running

### Symptom: Hook Not Running

Hook doesn't seem to execute when expected.

### Diagnostic Steps: Hook Not Running

**1. Check global enabled:**

```bash
grep "enabled:" .claude/hooks/config/global.yaml
```

Expected output: `enabled: true`

**2. Check hook enabled:**

```bash
grep "enabled:" .claude/hooks/<hook-name>/config.yaml
```

Expected output: `enabled: true`

**3. Verify registration:**

Check `.claude/settings.json` hooks section contains your hook.

**4. Check matcher:**

Ensure matcher pattern matches the tool being used:

```json
{
  "matcher": "Write|Edit"  // Matches Write and Edit tools
}
```

**5. Restart Claude Code:**

Hook registration changes require Claude Code restart.

### Solutions: Hook Not Running

- **Global disabled:** Set `enabled: true` in `config/global.yaml`
- **Hook disabled:** Set `enabled: true` in `config.yaml`
- **Not registered:** Add hook to `.claude/settings.json` and restart
- **Wrong matcher:** Update matcher pattern and restart
- **Wrong event:** Verify hook registered for correct event (PreToolUse, PostToolUse, etc.)

## Config Changes Not Taking Effect

### Symptom: Config Changes Not Taking Effect

Modified configuration but behavior unchanged.

### Diagnostic Steps: Config Changes Not Taking Effect

**1. Verify YAML syntax:**

Use online YAML validator (yamllint.com) to check syntax.

**2. Check file was saved:**

Reload file in editor to confirm changes are persistent.

**3. Test hook directly:**

```bash
echo '{"tool": "Write", "file_path": "test.md"}' | \
  .claude/hooks/<hook-name>/bash/<hook-name>.sh
```

**4. Check global enabled:**

Hook might be disabled globally even if per-hook config changed.

**5. Increase log level:**

```yaml
log_level: debug  # In config/global.yaml
```

### Solutions: Config Changes Not Taking Effect

- **YAML syntax error:** Fix syntax (check indentation, quotes, colons)
- **File not saved:** Save file and retry
- **Global disabled:** Enable globally in `config/global.yaml`
- **Caching issue:** Test hook directly to bypass any caching

### Important Notes

**Immediate effect (no restart):**

- enabled state
- enforcement mode
- patterns
- messages
- timeouts
- log levels

**Requires restart:**

- Hook registration
- Matchers
- Command paths

## Hook Errors

### Symptom: Hook Errors

Hook crashes or outputs error messages.

### Diagnostic Steps: Hook Errors

**1. View hook output:**

Claude Code shows hook stdout/stderr in terminal.

**2. Test hook manually:**

```bash
echo '{"tool": "Write", "file_path": "test.md", "new_string": "content"}' | \
  .claude/hooks/<hook-name>/bash/<hook-name>.sh

echo "Exit code: $?"
```

**3. Check dependencies:**

```bash
jq --version    # JSON processor
yq --version    # YAML processor (optional, has fallback)
git --version   # Git (if hook uses git commands)
```

**4. Check script permissions:**

```bash
ls -l .claude/hooks/<hook-name>/bash/<hook-name>.sh
# Should be executable on Unix/Linux/macOS
```

### Common Error Messages

**"Cannot load json-utils.sh":**

- **Cause:** Shared utilities not found
- **Solution:** Verify path in `source` statement uses `$SCRIPT_DIR`

**"jq: command not found":**

- **Cause:** jq not installed
- **Solution:** Install jq from <https://jqlang.github.io/jq/>

**"Invalid YAML syntax":**

- **Cause:** Malformed config.yaml or hook.yaml
- **Solution:** Validate YAML syntax, fix indentation/quotes

**"Permission denied":**

- **Cause:** Script not executable (Unix/Linux/macOS)
- **Solution:** `chmod +x .claude/hooks/<hook-name>/bash/<hook-name>.sh`

## False Positives

### Symptom: False Positives

Hook blocks operations that should be allowed.

### Solutions: False Positives

**1. Adjust patterns in hook config:**

Edit `.claude/hooks/<hook-name>/config.yaml`:

```yaml
patterns:
  excluded_paths:
    - 'docs/examples'
    - 'tests/fixtures'
  excluded_extensions:
    - '.example'
```

**2. Adjust global patterns:**

Edit `.claude/hooks/config/global.yaml` (affects all hooks):

```yaml
patterns:
  excluded_paths:
    - '.claude/temp'
    - 'node_modules'
```

**3. Change enforcement to warn:**

```yaml
enforcement: warn  # Instead of block
```

This allows operations but shows warnings for review.

**4. Temporarily disable hook:**

```yaml
enabled: false
```

Re-enable after fixing patterns.

## False Negatives

### Symptom: False Negatives

Hook doesn't block operations that should be blocked.

### Diagnostic Steps: False Negatives

**1. Check patterns:**

Ensure patterns match the problematic input.

**2. Test manually:**

```bash
echo '{"tool": "Write", "file_path": "problematic.bak"}' | \
  bash .claude/hooks/<hook-name>/bash/<hook-name>.sh
```

**3. Check enforcement mode:**

```yaml
enforcement: block  # Not warn or log
```

**4. Increase logging:**

```yaml
log_level: debug
```

### Solutions: False Negatives

- **Incomplete patterns:** Add missing patterns to config.yaml
- **Enforcement too lenient:** Change from warn/log to block
- **Logic error:** Fix hook script validation logic
- **Matcher too narrow:** Update matcher in settings.json

## Performance Issues

### Symptom

Hooks take too long to execute, causing timeouts.

### Diagnostic Steps

**1. Check timeout:**

```yaml
# In config.yaml
timeout_seconds: 10  # Default

# Or in global.yaml
execution:
  timeout_seconds: 30
```

**2. Profile hook execution:**

```bash
time echo '{"tool": "Write", "file_path": "test.md"}' | \
  bash .claude/hooks/<hook-name>/bash/<hook-name>.sh
```

**3. Identify slow operations:**

Add debug logging to find bottlenecks.

### Solutions

**1. Increase timeout:**

```yaml
timeout_seconds: 30  # Increase from default 10
```

**2. Optimize hook logic:**

- Use grep/sed instead of complex parsing
- Cache expensive operations
- Exit early when possible
- Avoid network calls

**3. Use faster implementation:**

Migrate from bash to Python/TypeScript for performance-critical hooks.

**4. Reduce scope:**

```yaml
patterns:
  excluded_paths:
    - 'large-directory'  # Skip expensive validation
```

## Debugging Workflow

### Step-by-Step Debugging

**1. Reproduce issue:**

Identify exact input that causes problem.

**2. Test hook directly:**

```bash
echo '{"tool": "Write", "file_path": "problematic-input"}' | \
  bash .claude/hooks/<hook-name>/bash/<hook-name>.sh
```

**3. Enable verbose logging:**

Add to hook script:

```bash
set -x  # Verbose execution
```

**4. Add debug output:**

```bash
echo "DEBUG: TOOL=$TOOL" >&2
echo "DEBUG: FILE_PATH=$FILE_PATH" >&2
```

**5. Check intermediate values:**

```bash
RESULT=$(some_command)
echo "DEBUG: RESULT=$RESULT" >&2
```

**6. Run tests:**

```bash
bash .claude/hooks/<hook-name>/tests/integration.test.sh
```

**7. Fix and verify:**

Make changes, test directly, then test in Claude Code.

## Getting Help

### Information to Provide

When seeking help with hook issues, provide:

1. **Hook name and version:** From hook.yaml (metadata file)
2. **Error message:** Full text including stack traces
3. **Input payload:** JSON that triggered the issue
4. **Hook script:** Relevant portions of the script
5. **Configuration:** config.yaml and relevant global.yaml sections
6. **Environment:** OS, bash version, dependency versions
7. **Steps to reproduce:** Exact steps to trigger the issue

### Where to Get Help

- **Official docs:** Use docs-management skill with keywords "hooks", "troubleshooting"
- **Repository issues:** Check existing issues for similar problems
- **Team discussion:** Ask team members with hook development experience

For more advanced debugging, see [debugging-guide.md](debugging-guide.md).
