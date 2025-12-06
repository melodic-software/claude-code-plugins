# Shared Hook Utilities

This directory contains shared utilities used by hooks in this plugin.

## hook-wrapper.sh

**Purpose:** Normalize CLAUDE_PLUGIN_ROOT paths for Windows compatibility.

**Problem:** On Windows, CLAUDE_PLUGIN_ROOT uses backslashes (C:\Users\...) but hook commands in hooks.json use forward slashes. This creates malformed paths that bash cannot execute.

**Solution:** This wrapper uses bash's path resolution (cd + pwd) to normalize mixed-separator paths into valid Unix paths.

**Workaround for:** <https://github.com/anthropics/claude-code/issues/11984>

### Usage

In hooks.json:

```json
{
  "type": "command",
  "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/shared/hook-wrapper.sh /hooks/your-hook/script.sh"
}
```

### Why Duplicated Across Plugins?

This file is intentionally duplicated in each plugin's `hooks/shared/` directory for **plugin isolation**:

1. **Self-contained plugins**: Each plugin must be fully functional without dependencies on other plugins
2. **Independent versioning**: Plugins can be installed/updated independently
3. **No cross-plugin dependencies**: A plugin should work even if it's the only plugin installed

The canonical source for this pattern is documented in the hook-wrapper.sh file itself.

**Maintenance note:** When updating this file, search for all copies across plugins:

```bash
git ls-files '**/hooks/shared/hook-wrapper.sh'
```

### Testing

Run the wrapper tests to verify functionality:

```bash
bash plugins/claude-code-observability/hooks/shared/tests/hook-wrapper.test.sh
```

---

**Last Updated:** 2025-12-06
