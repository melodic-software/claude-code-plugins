# Lesson 4: External Links and Resources

## Course Resources

- [IndyDevDan YouTube](https://www.youtube.com/@indydevdan) - Stay up to date with the latest content

## Related Tools and Documentation

- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code) - Official documentation for Claude Code

- [GitHub Issues](https://docs.github.com/en/issues) - Documentation for GitHub Issues (Prompt Input in PITER)

- [GitHub Webhooks](https://docs.github.com/en/webhooks) - Documentation for GitHub Webhooks (Trigger in PITER)

- [GitHub - Creating Webhooks](https://docs.github.com/en/webhooks/using-webhooks/creating-webhooks) - Official GitHub documentation for creating webhooks. Learn how to configure webhooks to trigger your AFK agents when issues are created, PRs are opened, or other events occur.

- [GitHub Pull Requests](https://docs.github.com/en/pull-requests) - Documentation for PRs (Review in PITER)

## Tunneling Tools (for Webhook Development)

- [ngrok - Getting Started](https://ngrok.com/docs/getting-started) - Set up secure tunnels to localhost for webhook development. ngrok enables you to expose your local development environment to the internet, essential for testing webhooks and triggers.

- [Cloudflare Tunnel - Get Started](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/get-started/) - Alternative to ngrok - create secure tunnels to your local environment using Cloudflare. Provides a production-grade solution for exposing webhooks and services without opening ports.

## Key Concepts from This Lesson

### PITER Framework

The four elements of AFK agents:

- **P - Prompt Input**: Use GitHub Issues as the entry point for your AFK agents
- **T - Trigger**: Use GitHub Webhooks to automatically start workflows
- **E - Environment**: Dedicated isolated environment for agent execution
- **R - Review**: Use Pull Requests for visibility and control

### AI Developer Workflows (ADWs)

Reusable agentic workflows that combine deterministic code with non-deterministic agents to solve problem classes. ADWs chain templates together to create comprehensive autonomous workflows.

### AFK (Away From Keyboard)

Moving beyond "in the loop" agentic coding to autonomous systems that run while you're not actively involved. The goal is to let your product build itself.
