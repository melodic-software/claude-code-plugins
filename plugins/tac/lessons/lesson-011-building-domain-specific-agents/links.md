# Lesson 11: External Links and Resources

## Course Resources

- [IndyDevDan YouTube](https://www.youtube.com/@indydevdan) - Stay up to date with the latest content

## Related Tools and Documentation

- [Claude Agent SDK Documentation](https://docs.claude.com/en/docs/claude-code/sdk/sdk-overview) - Official documentation for the Claude Agent SDK. This is the gateway to building custom agents programmatically.

## Key Concepts from This Lesson

### The Agent Evolution Path

| Stage | Focus | Description |
| ----- | ----- | ----------- |
| Better Agents | Prompt & Context | Improve existing agents through better prompts and context engineering |
| More Agents | Scaling Compute | Scale by running more agents in parallel |
| Custom Agents | Domain-Specific | Build specialized agents for your specific domain |

### The Core Four

| Element | Description |
| ------- | ----------- |
| Context | What the agent knows about your codebase |
| Model | Which Claude model (Haiku, Sonnet, Opus) |
| Prompt | System prompt and instructions |
| Tools | Available capabilities and functions |

### Agent Patterns

| Pattern | Purpose | Key Feature |
| ------- | ------- | ----------- |
| Pong Agent | System prompt control | Complete prompt override |
| Echo Agent | Custom tools | @tool decorator, in-memory MCP |
| Calculator Agent | Focused functionality | Consistent architecture |

### Model Selection Strategy

| Model | Best For | Characteristics |
| ----- | -------- | --------------- |
| Claude Haiku | Simple, fast tasks | Fastest, cheapest |
| Claude Sonnet | Balanced performance | Good all-rounder |
| Claude Opus | Complex reasoning | Most capable |

### System Prompt Strategies

| Strategy | Use Case | Warning |
| -------- | -------- | ------- |
| Append | Extend Claude Code capabilities | Builds on existing functionality |
| Override | Build true custom agents | Creates entirely new product |

### Best Practices

- The system prompt is your most important element with zero exceptions
- Use consistent codebase structure across all agents (prompts directory, same format)
- Use Query() for one-off prompts, Claude SDK Client for multi-turn conversations
- Test custom agents in isolation before production
- Log everything - adopt your agent's perspective
- Version control all system prompts and agent configurations
- Strip unnecessary tools for focused agents (default 15+ tools add overhead)
