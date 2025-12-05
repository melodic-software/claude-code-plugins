---
title: "Elite Context Engineering"
lesson: 9
level: Intermediate
slug: rd-framework-context-window-mastery
duration: "1:13:14"
url: https://agenticengineer.com/tactical-agentic-coding/course/rd-framework-context-window-mastery
---

## Overview

A focused agent is a performant agent. The context window is your agent's most precious resource - ephemeral, limited, and critical to success. Master context engineering through the R&D Framework.

## The R&D Framework

There are only two ways to manage your context window: **R**educe and **D**elegate. Every technique fits into one or both of these buckets.

![Elite Context Engineering](images/TacOilCard_L9_EliteContextEngineering.jpg)

## Key Concepts

### Context Engineering: The Name of the Game

A focused agent is a performant agent. Context engineering is the name of the game for high value engineering in the age of agents. Context is a critical in-agent leverage point that determines how an agent performs at any given task.

### Four Levels of Context Engineering

There are three levels of context engineering and a fourth hidden level if you're on the bleeding edge pushing into agentic engineering. Master all four levels to achieve complete context window mastery.

### Context Sweet Spot Range

There's a sweet spot - a range of context where your agent performs to its maximum possible capability for the task at hand. As you scale to hundreds and thousands of agent executions, hitting this sweet spot consistently becomes even more important.

### Hit the Core Four Bullseye

When aligned with the right model, prompt, tools, and the right range of context, we can hit the core four bullseye over and over. This directly increases our agentic coding KPIs and tells us if we're improving our capabilities.

### Search and Destroy Context Bloat

Search and destroy is the real skill in context engineering. The real trick is finding context agentically and then removing and delegating context so it doesn't create context rot and context bloat.

### Context Window: Precious & Temporal Resource

Your agent's context window is a precious, renewable, but limited temporal resource. It's ephemeral, resets, and is alive for only a certain amount of time. The state in your context window is critical to your success.

### What Gets Measured Gets Managed

Whenever you have a resource that determines your success, you must measure it so you can improve it. The context window is the single most important leverage point for effective agentic coding.

## Practical Techniques

### Measure Context Window State

Use `/context` command to measure your context window state.

### Avoid Vibe Coding

If you aren't actively paying attention to the state of your agent's context, you're just vibe coding and you'll only be able to tackle the lowest hanging fruit, which is already a massively saturated space.

### Install Token Counter in IDE

Install a tokenizer right in your IDE so you know what's coming into your agent's context. Token counters help you understand context consumption before files are loaded into your agent.

### Avoid MCP Server Bloat

Do not load MCP servers unless you need them. Default .mcp.json files can consume 10-12% of your entire context window, completely wasted unless you're actively using every single MCP server. Be very purposeful with your MCP servers.

### Delete Default .mcp.json Files

Get rid of default .mcp.json files completely. Don't use a default .mcp.json for your code base. This immediately clears up your context window and prevents wasteful token consumption on every agent instance.

### Load Specific MCP Server

```bash
claude --mcp-config path/to/specific-mcp.json
```markdown

### Context Priming Over Memory Files

Use context priming over claude.md or similar auto-loading memory files. Context priming uses dedicated reusable prompts (custom slash commands) to set up your agent's initial context specifically for the task type at hand, avoiding bloated memory files.

### Problems with Always-On Context

Always-on context like claude.md files is not dynamic or controllable. Engineering work constantly changes, but memory files only grow. Eventually they become bloated with irrelevant context, and in worst case, contradictory information.

### Context Priming Command

Use `/prime` command for context priming.

## The Core Four

| Component | Description |
| --------- | ----------- |
| Model | Right model for the task |
| Prompt | Well-crafted instructions |
| Tools | Appropriate tool access |
| Context | Right range of context |

## R&D Framework Summary

| Strategy | Purpose |
| -------- | ------- |
| **Reduce** | Remove unnecessary context, avoid bloat |
| **Delegate** | Offload context to sub-agents or external sources |
