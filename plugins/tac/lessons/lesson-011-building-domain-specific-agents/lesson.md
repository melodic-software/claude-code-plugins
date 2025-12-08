---
title: "Building Domain-Specific Agents"
lesson: 11
level: Advanced
slug: building-domain-specific-agents
duration: "67:30"
url: https://agenticengineer.com/tactical-agentic-coding/course/building-domain-specific-agents
---

## Overview

Create specialized agents tailored for specific domains and use cases. Learn to build agents that understand your business logic, domain constraints, and specialized workflows for maximum effectiveness.

## Key Concepts

### Engineer Specialized Agents

Better agents -> More agents -> Custom agents. Move from generic agents to domain-specific powerhouses with full SDK control.

### The Agent Evolution Path

Every engineer follows the same path: better agents (prompt & context engineering), more agents (scaling compute), then custom agents (domain-specific solutions).

### The Mismatch Problem

Out-of-the-box agents are built for everyone's codebase, not yours. This mismatch costs hundreds of hours and millions of tokens as your codebase grows.

### Where The Alpha Is

All the alpha in engineering is in hard, specific problems that most engineers and agents can't solve out of the box. Custom agents let you pass domain-specific knowledge directly to your agents.

### Master The Core Four

Custom agents give you full control over the Core Four: Context, Model, Prompt, and Tools. Scale them beyond defaults to solve domain-specific problems.

### Template Your Engineering

Custom agents let you template your engineering directly into your agent. Push one agent, one prompt, one purpose to its limits for maximum effectiveness.

### Scale Beyond The Rest

Master agents by going to the bare metal. Deploy effective compute by teaching agents your domain. Scale your compute far beyond what generic agents can achieve.

## Agent Patterns

### The Pong Agent Pattern

The simplest custom agent that demonstrates total system prompt control. Override the system prompt completely to create an entirely new product.

### The Echo Agent Pattern

Add custom tools to your agent using the @tool decorator. Build MCP servers in-memory and give your agent specialized capabilities.

### The Calculator Agent Pattern

Progress to more capable custom agents with focused functionality. Use consistent codebase architecture across all custom agents for better agent navigation.

## Technical Guidance

### The System Prompt Is Everything

The system prompt is your most important element with zero exceptions. It affects EVERY user prompt the agent runs. Touch the system prompt, and you change the product entirely.

### Critical Warning

When you override the system prompt, this is NOT Claude Code anymore. You've created a new product entirely. Be very careful with system prompt modifications.

### Building Custom Tools

Tools are built with @tool decorator. The description tells your agent how to use the tool. Create SDK MCP servers in-memory for specialized functionality.

### Model Selection Strategy

Choose wisely: Claude Haiku for simple, fast tasks. Claude Sonnet for balanced performance. Claude Opus for complex reasoning. Match model to task complexity.

### Tool Overhead Warning

Default Claude Code includes 15+ tools that consume precious context even if unused. Every tool adds to context window overhead. Strip unnecessary tools for focused agents.

### Context Is Precious

15 extra tools consume space in your agent's mind. Use /context command to understand what's going into your agent. Control this for better performance.

### System Prompt Strategies

Two approaches: Append to extend Claude Code capabilities, or Override to build true custom agents. Version control all system prompts for reproducibility.

### Leverage Consistent Architecture

Use consistent codebase structure across all agents: prompts directory, same format. It's easy for your team to read and most importantly for your agents to navigate.

### Query vs Client Pattern

Use Query() for one-off prompts, Claude SDK Client for multi-turn conversations. Track conversation state explicitly for complex agent interactions.

## Advanced Topics

### Multi-Agent Systems

Progress from single agents to multi-agent orchestration. Build agent-by-agent handoff systems with dedicated workflows for complex problem solving.

### Deploy Agents Everywhere

Deploy agents in scripts, data streams, terminals, and UIs. Think about repeat workflows that benefit from agents. Find constraints in personal workflows and products.

### Test in Isolation

Test custom agents in isolation before production. Log everything - adopt your agent's perspective. Version control is critical for agent configurations.

## Summary Table

| Pattern | Purpose | Key Feature |
| ------- | ------- | ----------- |
| Pong Agent | System prompt control | Complete prompt override |
| Echo Agent | Custom tools | @tool decorator, in-memory MCP |
| Calculator Agent | Focused functionality | Consistent architecture |
