# response-quality

Enforces response quality standards including mandatory source citations for Claude Code.

## Overview

This plugin ensures Claude always discloses where information comes from, enabling users to verify claims and assess reliability.

## Features

### Source Citation Enforcement

Every response with factual claims must cite sources using these categories:

| Category | Format | When to Use |
| -------- | ------ | ----------- |
| **FILE** | `[FILE: path/to/file.ts:L42-L56]` | Information from reading project files |
| **WEB** | `[WEB: https://example.com]` | Information from web search or fetch |
| **MCP** | `[MCP: server-name/tool-name]` | Information from MCP tools |
| **TRAINING** | `[TRAINING: knowledge cutoff Jan 2025]` | General knowledge from training data |
| **INFERRED** | `[INFERRED: from X]` | Conclusions drawn from reasoning |

### Response Format

Responses with factual claims include a Sources section:

```markdown
Based on the handler implementation [FILE: src/api/users.ts:L23-L45]...

---
## Sources
- [FILE: src/api/users.ts:L23-L45] - User handler implementation
- [WEB: https://react.dev/hooks] - React hooks documentation
- [TRAINING] - General knowledge (cutoff: Jan 2025)
```

### Exempt Responses

No sources required for:

- Procedural statements ("Running npm install now...")
- Error message reporting (self-evident from tool output)
- Clarifying questions to the user
- Simple acknowledgments

## Installation

```bash
/plugin install response-quality@claude-code-plugins
```

## How It Works

1. **SessionStart hook** - Injects citation requirements into Claude's context at session start
2. **Memory file** - Reference documentation for citation format (in `memory/source-citation-requirements.md`)

## Configuration

The plugin works out of the box with no configuration required.

## Verification

After installation, test by:

1. Starting a new session - citation context should be injected
2. Asking a question requiring file reads - should see `[FILE]` citations
3. Asking for web search - should see `[WEB]` citations and Sources section
4. Asking general knowledge question - should see `[TRAINING]` tag

## Version History

- **1.0.0** - Initial release with source citation enforcement

## License

MIT
