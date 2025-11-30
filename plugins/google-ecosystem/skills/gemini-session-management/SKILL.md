---
name: gemini-session-management
description: Central authority for Gemini CLI session management. Covers session resume, retention policies, session browser, and cleanup configuration. Delegates 100% to gemini-cli-docs for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# Gemini Session Management

## MANDATORY: Invoke gemini-cli-docs First

> **STOP - Before providing ANY response about Gemini sessions:**
>
> 1. **INVOKE** `gemini-cli-docs` skill
> 2. **QUERY** for the specific session topic
> 3. **BASE** responses EXCLUSIVELY on official documentation loaded

## Overview

Meta-skill for managing Gemini CLI sessions. Sessions preserve conversation history and can be resumed, searched, and configured with retention policies.

## When to Use This Skill

**Keywords:** session, resume, /resume, session browser, retention, maxAge, maxCount, --list-sessions, --delete-session

**Use this skill when:**

- Resuming a previous session
- Configuring session retention
- Browsing past sessions
- Managing session storage
- Understanding session limits

## Session Resume

### Resume Last Session

```bash
gemini --resume
# or
gemini -r
```

### Resume via Browser

In an active session:

```text
/resume
```

Opens interactive session browser to search and select.

## Session Retention

Configure automatic cleanup in `settings.json`:

```json
{
  "general": {
    "sessionRetention": {
      "maxAge": "7d",
      "maxCount": 100,
      "minRetention": "1d"
    }
  }
}
```

| Setting | Description | Example |
|---------|-------------|---------|
| `maxAge` | Maximum session age | `"7d"`, `"24h"` |
| `maxCount` | Maximum sessions to keep | `100`, `50` |
| `minRetention` | Minimum time before deletion | `"1d"`, `"12h"` |

## Session Limits

Configure turn limits:

```json
{
  "general": {
    "maxSessionTurns": 100
  }
}
```

## Session Storage

Sessions are stored in:

```text
~/.gemini/tmp/<project_hash>/
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--resume`, `-r` | Resume last session |
| `--list-sessions` | List available sessions |
| `--delete-session <id>` | Delete specific session |

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
|-------|----------------|
| Resume | `--resume flag`, `resume session`, `/resume command` |
| Browser | `session browser`, `search sessions`, `/resume interactive` |
| Retention | `sessionRetention`, `maxAge maxCount`, `session cleanup` |
| Limits | `maxSessionTurns`, `session limits`, `turn limits` |
| Storage | `session storage`, `~/.gemini/tmp`, `session location` |
| Management | `--list-sessions`, `--delete-session`, `session management` |

## Quick Decision Tree

**What do you want to do?**

1. **Resume last session** -> `gemini --resume` or `gemini -r`
2. **Browse past sessions** -> `/resume` in active session
3. **Configure retention** -> Edit sessionRetention in settings.json
4. **List all sessions** -> `gemini --list-sessions`
5. **Delete session** -> `gemini --delete-session <id>`
6. **Set turn limits** -> Configure maxSessionTurns

## Best Practices

1. **Regular cleanup**: Configure retention to avoid disk bloat
2. **Name sessions**: Use descriptive prompts for easy browsing
3. **Resume for context**: Continue complex conversations
4. **Delete sensitive**: Remove sessions with sensitive data

## Verification Checkpoint

- [ ] Did I invoke gemini-cli-docs skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

## References

Query `gemini-cli-docs` for official documentation on:

- "session management"
- "session resume"
- "sessionRetention"
