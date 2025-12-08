# Shared Hook Infrastructure

This directory contains shared hook infrastructure used by all plugins in this marketplace repository.

## Files

- `hook-wrapper.py` - Cross-platform Python wrapper that normalizes paths and finds bash on Windows

## Why This Exists

On Windows, Claude Code sets `CLAUDE_PLUGIN_ROOT` with backslashes (`C:\Users\...`), but hook commands in `hooks.json` use forward slashes. This causes path resolution failures before bash can even run.

The `hook-wrapper.py` script:

1. Reads `CLAUDE_PLUGIN_ROOT` environment variable
2. Normalizes paths using Python's `pathlib`
3. Finds bash on Windows (Git Bash, etc.)
4. Executes the target script with proper paths

## Usage in hooks.json

Plugins reference this shared wrapper using a relative path from their plugin root:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "python \"${CLAUDE_PLUGIN_ROOT}/../../shared/hooks/hook-wrapper.py\" /hooks/your-hook/script.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

The path `${CLAUDE_PLUGIN_ROOT}/../../shared/hooks/` navigates from the plugin directory up to the repository root and into the shared directory.

## Path Resolution

Given:
- `${CLAUDE_PLUGIN_ROOT}` = `/path/to/claude-code-plugins/plugins/plugin-name`
- Relative path to shared = `/../../shared/hooks/`

Result: `/path/to/claude-code-plugins/shared/hooks/hook-wrapper.py`

This works for all installation modes:
- **Local directory**: Plugins point to git repo, shared directory accessible
- **Git/GitHub clone**: Entire repo is cloned, preserving directory structure

## Workaround Reference

This infrastructure works around: https://github.com/anthropics/claude-code/issues/11984
