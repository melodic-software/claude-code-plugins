# Agentic Layer vs Application Layer

## The Two Layers

Every codebase in the agentic age has two distinct layers:

| Layer | Purpose | Contents |
| ------- | --------- | ---------- |
| **Agentic Layer** | How agents operate | ADWs, prompts, plans, templates, hooks |
| **Application Layer** | What agents work on | Application code, infrastructure, database |

## The Agentic Layer

The ring around your codebase - machines that operate with your judgment.

### Contents

```text
Agentic Layer:
├── .claude/commands/    # Agent vocabulary (slash commands)
├── .claude/hooks/       # Event-driven automation
├── specs/               # Plans and specifications
├── adws/                # AI Developer Workflows
├── agents/              # Agent output and state
└── trees/               # Worktrees for isolation
```markdown

### Activities

Working ON the agentic layer means:

- Creating slash command templates
- Building composed workflows
- Improving agent context (CLAUDE.md)
- Adding hooks and triggers
- Designing primitives
- Setting up observability
- Configuring worktree isolation

## The Application Layer

The traditional codebase that agents operate on.

### Contents

```text
Application Layer:
├── src/                 # Application source code
├── app/                 # Main application
├── lib/                 # Libraries and utilities
├── infra/               # Infrastructure as code
├── database/            # Database migrations/schema
└── config/              # Configuration files
```markdown

### Activities

Working IN the application layer means:

- Writing application code directly
- Managing infrastructure
- Configuring databases
- DevOps tasks
- Manual bug fixes

## Time Investment

| Layer | Target | Why |
| ------- | -------- | ----- |
| Agentic | 50%+ | Builds leverage, compounds value |
| Application | <50% | Agents will handle this |

### Why 50%+ Agentic?

1. **Parabolic returns**: 10 minutes invested -> 2+ hours value
2. **Compounds over time**: More workflows = more automation
3. **Problem classes**: Solve categories, not one-offs
4. **Leverage multiplier**: Agents work 24/7

## Signs You're in Wrong Layer

### Too Much Application Work

- Manually fixing bugs you've fixed before
- Writing similar code repeatedly
- Doing tasks agents could do
- Not building templates

### Healthy Agentic Investment

- Creating templates for common tasks
- Building composed workflows
- Improving agent context
- Adding feedback loops
- Scaling to new problem classes

## Layer Interaction

The agentic layer OPERATES ON the application layer:

```text
┌─────────────────────────────────────┐
│         AGENTIC LAYER              │
│  ┌───────────────────────────────┐  │
│  │     APPLICATION LAYER         │  │
│  │  (src/, app/, lib/, etc.)     │  │
│  └───────────────────────────────┘  │
│                                     │
│  [ADWs] [Commands] [Hooks] [Plans]  │
└─────────────────────────────────────┘
```markdown

The agentic layer surrounds and operates on the application layer.

## Decision Framework

When starting any task, ask:

1. **Is this application work?**
   - Can I build a template instead?
   - Will I do this again?

2. **Is this agentic work?**
   - Will this help agents do application work?
   - Does this solve a problem class?

3. **Default to agentic**
   - If unsure, invest in agentic layer
   - Build for reuse, not one-offs

## The Vision

**Today:**

- You write application code
- Agents assist occasionally
- 80% application, 20% agentic

**Tomorrow:**

- Agents write application code
- You architect and review
- 20% application, 80% agentic

**The Future:**

- Agents handle problem classes autonomously
- You design new capabilities
- Minimal application layer work

## Cross-References

- @the-guiding-question.md - Daily decision framework
- @agentic-layer-structure.md - Layer organization
- @tac-philosophy.md - Stop coding mindset
- @zte-progression.md - Target state
