# Registry schema (`registry.json`)

Canonical shape the skill reads and writes at `${CLAUDE_PLUGIN_DATA}/registry.json`. `scripts/registry_manager.py validate` enforces required fields, category/status enums, URL prefix, ISO date fields, and duplicate-number detection.

```json
{
  "version": 1,
  "issues": [
    {
      "number": 15840,
      "repo": "anthropics/claude-code",
      "title": "CLAUDE_ENV_FILE not provided to SessionStart hooks",
      "url": "https://github.com/anthropics/claude-code/issues/15840",
      "category": "blocking",
      "status": "open",
      "feature": "CLAUDE_ENV_FILE",
      "impact": "Cannot use CLAUDE_ENV_FILE for state sharing between hooks",
      "workaround": "Use temp files keyed by CLAUDE_SESSION_ID",
      "affected_files": [
        "docs/claude-code-quirks.md",
        "docs/hook-conventions.md"
      ],
      "blocked_work": "Hook configuration externalization convention",
      "last_checked": "2026-03-24",
      "added": "2026-03-24"
    }
  ]
}
```

Categories: `blocking`, `degraded`, `cosmetic`, `fixed`, `feature-request`, `informational`. Statuses: `open`, `closed`.
