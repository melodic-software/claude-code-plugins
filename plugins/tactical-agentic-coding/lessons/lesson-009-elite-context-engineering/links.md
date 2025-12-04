# Lesson 9: External Links and Resources

## Course Resources

- [IndyDevDan YouTube](https://www.youtube.com/@indydevdan) - Stay up to date with the latest content

## Related Tools and Documentation

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code) - Official documentation for Claude Code

## Key Concepts from This Lesson

### The R&D Framework

| Strategy | Purpose | Examples |
| -------- | ------- | -------- |
| **Reduce** | Remove unnecessary context | Delete default .mcp.json, avoid bloated memory files |
| **Delegate** | Offload to sub-agents | Use specialized agents, external MCP servers |

### Four Levels of Context Engineering

1. Basic context awareness
2. Active context management
3. Strategic context engineering
4. Advanced agentic context (bleeding edge)

### Context Sweet Spot

- Too little context: Agent lacks necessary information
- Too much context: Context rot, bloat, contradictory information
- Sweet spot: Maximum capability for the task at hand

### The Core Four Bullseye

| Component | Description |
| --------- | ----------- |
| Model | Right model for the task |
| Prompt | Well-crafted instructions |
| Tools | Appropriate tool access |
| Context | Right range of context |

### Practical Commands

| Command | Purpose |
| ------- | ------- |
| `/context` | Measure context window state |
| `/prime` | Context priming for specific task types |
| `claude --mcp-config path/to/file.json` | Load specific MCP server |

### Anti-Patterns to Avoid

- **Vibe Coding**: Not paying attention to context state
- **MCP Server Bloat**: Loading all MCP servers by default (10-12% waste)
- **Always-On Context**: Bloated memory files that only grow
- **Default .mcp.json**: Wasteful token consumption on every instance

### Best Practices

- Install token counter in IDE
- Use context priming over memory files
- Load MCP servers only when needed
- Measure context to manage it
- Search and destroy context bloat
