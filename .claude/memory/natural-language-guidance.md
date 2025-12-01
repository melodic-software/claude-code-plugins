# Natural Language Prompting for Agentic Systems

## Core Principle

When writing instructions for autonomous agentic CLI tools (Claude Code, sub-agents, etc.), **prefer natural language that describes intent and desired outcomes** over rigid procedural steps.

## Why Natural Language?

**Maintainability**: Tool interfaces, APIs, and available functions evolve over time. Natural language instructions remain valid even as implementation details change, while rigid procedural steps become brittle and require constant maintenance.

**Adaptability**: Agentic systems can interpret natural language instructions and adapt their approach based on available tools, context, and changing conditions. Rigid steps cannot adapt to unexpected scenarios.

**Clarity**: Natural language focuses on "what" and "why" rather than "how", making instructions clearer and more understandable to both humans and AI systems.

## Scope of Application

This principle applies to:

- **Slash commands** (`.claude/commands/*.md`)
- **Skills** (`SKILL.md` files)
- **Sub-agent prompts** (Task tool invocations)
- **Any autonomous Claude Code instructions** (hooks, configurations, etc.)

This does NOT typically apply to:

- **End-user documentation** (guides remain human-focused)
- **System logs or audit trails** (require precision and structure)

## Exception: Scripts and Automation

**Scripts are encouraged** when they provide clear, stable contracts. As long as the script's interface (parameters, inputs, outputs) is well-defined and documented, calling scripts from natural language instructions is appropriate.

The key distinction:

- Natural language to describe **what** to achieve
- Scripts to implement **how** to achieve it (with clear contracts)
- Rigid procedural steps in natural language (combines worst of both)

## Guidance

**When writing instructions for agentic systems:**

1. **Describe the desired outcome**: What should be accomplished?
2. **Explain the context**: Why is this needed? What's the purpose?
3. **Specify constraints**: What must be true? What should be avoided?
4. **Trust the agent**: Let the agentic system determine the best approach using available tools

**Avoid:**

- Enumerating exact tool sequences that may become outdated
- Over-specifying implementation details that the agent can infer
- Creating brittle workflows that break when tool interfaces change

## Philosophy

Agentic CLI tools like Claude Code are designed to understand intent and autonomously determine execution paths. By using natural language, we create a more resilient system where instructions remain valid even as the underlying tooling evolves.

**Think of it as:** Writing a mission briefing rather than step-by-step assembly instructions.

**Last Updated:** 2025-11-30
