# Lesson 7: External Links and Resources

## Course Resources

- [IndyDevDan YouTube](https://www.youtube.com/@indydevdan) - Stay up to date with the latest content

## Related Tools and Documentation

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code) - Official documentation for Claude Code

- [Git Worktrees Documentation](https://git-scm.com/docs/git-worktree) - Git worktrees for parallel agent environments

- [Docker Documentation](https://docs.docker.com/) - Containerization for agent isolation

## Key Concepts from This Lesson

### Three Levels of Agentic Coding

| Level | Description | Human Touchpoints |
| ----- | ----------- | ----------------- |
| In-Loop | Interactive prompting | Constant |
| Out-Loop | AFK agents (PITER) | 2 (prompt + review) |
| Zero-Touch | Self-shipping codebase | 1 (prompt only) |

### ZTE Workflow

1. Plan the feature
2. Build the implementation
3. Test functionality
4. Review quality
5. Generate documentation
6. Ship to production

### The Secret: Composable Agentic Primitives

The real power isn't in following a rigid SDLC - it's in building composable primitives that can be arranged to solve any engineering problem class.

### Agent Isolation Methods

- **Git Work Trees**: Multiple checkouts of the same repo for parallel agent execution
- **Docker Containers**: Isolated environments with full dependency control
- **Agent Containerization Frameworks**: Purpose-built isolation for AI agents

### Agentic KPIs (Final Review)

- **Attempts**: Number of tries to complete a task (want DOWN)
- **Size**: Scope of work completed per session (want UP)
- **Streak**: Consecutive successful completions (want UP)
- **Presence**: Human intervention required (want DOWN - target is 1 touchpoint)
