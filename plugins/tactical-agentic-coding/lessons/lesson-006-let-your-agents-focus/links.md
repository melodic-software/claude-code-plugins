# Lesson 6: External Links and Resources

## Course Resources

- [IndyDevDan YouTube](https://www.youtube.com/@indydevdan) - Stay up to date with the latest content

## Related Tools and Documentation

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code) - Official documentation for Claude Code

- [Playwright MCP](https://github.com/anthropics/claude-code/tree/main/packages/mcp-server-playwright) - Browser automation for agents. Enable your agents to interact with web pages through the Playwright MCP server for UI testing and web scraping.

## Key Concepts from This Lesson

### Review vs Testing

- **Testing**: Asks "does it work?" - validates functionality
- **Review**: Asks "is what we built what we asked for?" - validates against the original plan

### SDLC as Questions

| Step | Question |
| ---- | -------- |
| Plan | What are we building? |
| Build | Did we make it real? |
| Test | Does it work? |
| Review | Is what we built what we planned? |
| Document | How does it work? |

### Agentic KPIs (Reminder)

- **Attempts**: Number of tries to complete a task (want DOWN)
- **Size**: Scope of work completed per session (want UP)
- **Streak**: Consecutive successful completions (want UP)
- **Presence**: Human intervention required (want DOWN)

### Three Constraints of Agentic Engineers

1. The context window
2. The complexity of our codebase and the problem we're solving
3. Our abilities

Specialized agents bypass two out of three of these constraints.

### Context Engineering Principles

- **Minimum Context Principle**: Use the minimum context required to solve the problem
- **Avoid Context Pollution**: Overloaded context windows lead to confused agents
- **Free Up the Context Window**: Give agents full space to focus on one problem
