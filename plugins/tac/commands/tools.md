---
description: List all available Claude Code tools with their parameters and capabilities.
---

# Tools - Know What You Can Do

List all available tools showing their parameters, capabilities, and typical use cases.

Format the output as TypeScript function signatures for clarity:

```typescript
// Core File Operations
Read(file_path: string, offset?: number, limit?: number): string
Write(file_path: string, content: string): void
Edit(file_path: string, old_string: string, new_string: string): void

// Search Operations
Glob(pattern: string, path?: string): string[]
Grep(pattern: string, path?: string, options?: GrepOptions): string[]

// Execution
Bash(command: string, timeout?: number): { stdout: string, stderr: string }

// Web Operations
WebFetch(url: string, prompt: string): string
WebSearch(query: string): SearchResult[]

// Agent Operations
Task(prompt: string, subagent_type: string): string

// MCP Tools (if configured)
// List any available MCP server tools
```

After listing tools, note:

- Which tools require permission vs auto-allowed
- Any tool restrictions in current settings
- MCP servers available (if any)

This helps understand current capabilities before starting a task.
