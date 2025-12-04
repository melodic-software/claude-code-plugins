# Lesson 12: External Links and Resources

## Course Resources

- [IndyDevDan YouTube](https://www.youtube.com/@indydevdan) - Stay up to date with the latest content

## Related Tools and Documentation

- [Claude Code Agent SDK Documentation (Python)](https://docs.claude.com/en/api/agent-sdk/python) - Official Python SDK documentation for building custom agents programmatically. The extensibility of Claude Code makes multi-agent orchestration possible.

## Key Concepts from This Lesson

### The Agent Evolution Path

| Stage | Focus | Description |
| ----- | ----- | ----------- |
| Base Agents | Getting started | Using agents out of the box |
| Better Agents | Prompt & Context | Improving agent performance |
| More Agents | Scaling Compute | Running multiple agents |
| Custom Agents | Domain-Specific | Building specialized agents |
| Orchestrated Agents | Fleet Command | Commanding agent fleets |

### The Three Pillars of Multi-Agent Orchestration

| Pillar | Description | Purpose |
| ------ | ----------- | ------- |
| Orchestrator Agent | Unified interface | Single point of command for all agents |
| CRUD Operations | Agent lifecycle | Create, Read, Update, Delete agents at scale |
| Observability | Real-time monitoring | Track performance, costs, and results |

### PETER System for Out-Loop Multi-Agent

| Component | Description |
| --------- | ----------- |
| P - Prompt | Input to the orchestrator |
| T - Trigger | HTTP or event-based activation |
| E - Environment | Execution context |
| R - Review | Observability and monitoring |

### Best Practices

- Command your fleet through a single orchestrator interface
- Each specialized agent serves one purpose with focused context
- Delete agents after they produce concrete results - keep them lean
- Apply R&D Framework at scale: Reduce orchestrator context, Delegate to sub-agents
- Observability is essential - if you can't measure it, you can't improve it
- Track the Core Four (Context, Model, Prompt, Tools) across your entire fleet
- The rate at which you create and command agents becomes your output constraint
