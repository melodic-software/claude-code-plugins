# Agent Evolution Path

The journey from generic agents to domain-specific powerhouses.

## The Four Levels

| Level | Name | Description | When to Use |
| ------- | ------ | ------------- | ------------- |
| **1** | Base Agents | Out-of-the-box agents (Claude Code, Codex CLI, Gemini CLI) | Exploring, prototyping, generic tasks |
| **2** | Better Agents | Prompt engineering + context engineering | When defaults aren't good enough |
| **3** | More Agents | Scaling compute with multiple agents | When single agent can't handle scope |
| **4** | Custom Agents | Domain-specific solutions with full SDK control | Domain-specific problems, repeat workflows |

## Progression Triggers

### Level 1 -> Level 2 (Base -> Better)

Move to Better Agents when:

- Default prompts don't capture your intent
- Agent needs domain context to be effective
- Results are inconsistent without guidance
- You're repeating the same context setup

### Level 2 -> Level 3 (Better -> More)

Move to More Agents when:

- Single agent can't handle task complexity
- Tasks have natural parallelization
- Different aspects need different expertise
- Context window is being exhausted

### Level 3 -> Level 4 (More -> Custom)

Move to Custom Agents when:

- Solving repeat workflows with agents
- Domain-specific problems that out-of-box can't solve
- Need programmatic agent control
- Keeping costs down while maintaining performance
- Need permission checks and governance
- Want to stay out of the loop

## The Mismatch Problem

> "Out-of-the-box agents are built for everyone's codebase, not yours. This mismatch can cost you hundreds of hours and millions of tokens."

**Generic agents fail when:**

- Your domain has specialized terminology
- Your codebase has unique patterns
- You need consistent, repeatable results
- Security/governance is required
- Token efficiency matters

**Custom agents solve this by:**

- Passing domain-specific knowledge directly
- Creating targeted, repeatable workflows
- Protecting codebases from wrong tool calls
- Pushing "one agent, one prompt, one purpose" to limits

## Where the Alpha Is

> "All the alpha in engineering is in the hard specific problems that most engineers and most agents can't solve out of the box."

**Generic problems** = Generic agents work fine
**Domain-specific problems** = Custom agents unlock value

The alpha is in teaching your agents what YOU know about YOUR domain.

## Decision Framework

**Stay at Base/Better when:**

- Operating in the loop (prompting back and forth)
- Workflow is generic enough
- Exploring or prototyping
- Tasks are short-lived and lightweight
- You need a balanced generalist agent

**Move to Custom when:**

- Need programmatic, repeatable agents
- Domain expertise is required
- Cost optimization matters
- Governance/security is required
- Building products with agents

## Key Quote

> "It's not about what you can do anymore. It's about what you can teach your agents to do."

## Cross-References

- @core-four-custom.md - Controlling the Core Four in custom agents
- @system-prompt-architecture.md - Override vs append patterns
- @custom-agent-design skill - Workflow for designing custom agents
