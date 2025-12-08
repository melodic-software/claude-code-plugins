# Lesson 008 Plan: The Agentic Layer - The Meta-Tactic

## Summary

Implement Lesson 008 "The Agentic Layer" for the tac plugin. This lesson teaches the meta-tactic: Prioritize Agentics. Spend 50%+ of engineering time on the agentic layer, not the application layer.

## Core Tactic

**Prioritize Agentics** - More than half of your engineering time should be spent on the agentic layer rather than the application layer. This tactic represents all other tactics compressed into one.

## Source Material Validated

- [x] Lesson content at `plugins/tac/lessons/lesson-008-the-agentic-layer/`
- [x] Analysis at `plugins/tac/analysis/lesson-008-analysis.md`
- [x] Companion repo at `D:\repos\gh\disler\tac-8` (5 sub-applications)
- [x] Official Claude Code docs validated

## Key Concepts from Lesson

### The Two Layers

| Layer | Contents | Time Investment |
| ------- | ---------- | ----------------- |
| **Agentic Layer** | ADWs, prompts, plans, templates, hooks | 50%+ of your time |
| **Application Layer** | DevOps, infrastructure, database, application code | <50% of your time |

### The Guiding Question

> "Am I working on the agentic layer or am I working on the application layer?"

This single question compresses all tactics, KPIs, and leverage points into one daily decision framework.

### Minimum Viable Agentic Layer

```text
specs/              # Plans for agents to follow
.claude/commands/   # Agentic prompts
adws/              # AI Developer Workflows
```yaml

### Gateway Scripts

Entry points into agentic coding:

- `adw_prompt.py` - Ad-hoc prompt execution
- `adw_slash_command.py` - Slash command execution
- `adw_chore_implement.py` - Composed workflow (plan + implement)

## Components to Create

### Memory Files (4 files)

Location: `plugins/tac/memory/`

| File | Purpose | Priority |
| ------ | --------- | ---------- |
| `agentic-layer-structure.md` | Minimum viable vs scaled layer structures | P1 |
| `the-guiding-question.md` | Daily decision framework for prioritizing agentics | P1 |
| `gateway-script-patterns.md` | Entry point scripts for agentic coding | P2 |
| `agentic-vs-application.md` | Clear separation of layers | P2 |

### Skills (4 skills)

Location: `plugins/tac/skills/`

| Skill | Purpose | Tools |
| ------- | --------- | ------- |
| `agentic-layer-audit` | Audit codebase for agentic layer coverage | Read, Grep, Glob |
| `minimum-viable-agentic` | Guide creation of minimum viable agentic layer | Read, Grep, Glob |
| `task-based-multiagent` | Set up task-based multi-agent systems | Read, Grep, Glob |
| `gateway-script-design` | Design gateway scripts for agentic entry points | Read, Grep, Glob |

### Commands (2 commands)

Location: `plugins/tac/commands/`

| Command | Purpose | Arguments |
| --------- | --------- | ----------- |
| `audit-layer` | Audit codebase for agentic layer components | `$ARGUMENTS` - target directory |
| `scaffold-layer` | Scaffold minimum viable agentic layer | `$ARGUMENTS` - project name |

### Agents (2 agents)

Location: `plugins/tac/agents/`

| Agent | Purpose | Tools | Model |
| ------- | --------- | ------- | ------- |
| `layer-auditor` | Analyze codebase for agentic layer components | Read, Glob, Grep | haiku |
| `layer-scaffolder` | Create minimum viable agentic layer structure | Read, Write, Bash | sonnet |

## Implementation Details

### Memory: agentic-layer-structure.md

Content outline:

- Minimum viable structure (specs, commands, adws)
- Scaled structure (triggers, tests, state, hooks)
- Directory organization patterns
- What belongs in each directory
- Time investment guidance (50%+ on agentic)

### Memory: the-guiding-question.md

Content outline:

- The guiding question explained
- How to apply daily
- Agentic layer activities
- Application layer activities
- Decision framework
- Cross-reference to all 8 tactics

### Memory: gateway-script-patterns.md

Content outline:

- What is a gateway script
- `adw_prompt.py` pattern (direct prompts)
- `adw_slash_command.py` pattern (templates)
- `adw_chore_implement.py` pattern (composed)
- Subprocess execution safety
- Output file organization

### Memory: agentic-vs-application.md

Content outline:

- Clear layer separation
- Agentic layer contents
- Application layer contents
- When to invest in each
- Signs of under-investment in agentic layer

### Skill: agentic-layer-audit

Workflow:

1. Scan for .claude/commands/ directory
2. Check for specs/ directory
3. Look for adws/ or workflow scripts
4. Identify hooks configuration
5. Report coverage and gaps

### Skill: minimum-viable-agentic

Workflow:

1. Identify current state
2. Determine MVP requirements
3. Create scaffold plan
4. Guide implementation
5. Validate setup

### Skill: task-based-multiagent

Workflow:

1. Design task file format
2. Set up worktree isolation
3. Configure cron trigger
4. Implement status tracking
5. Enable parallel execution

### Skill: gateway-script-design

Workflow:

1. Identify entry point needs
2. Design script architecture
3. Plan output organization
4. Configure retry logic
5. Implement rich console output

### Command: audit-layer

Steps:

1. Scan target directory for agentic components
2. Check .claude/commands/ existence and contents
3. Check specs/ existence and contents
4. Check adws/ existence and contents
5. Report coverage percentage and gaps

### Command: scaffold-layer

Steps:

1. Create specs/ directory
2. Create .claude/commands/ with basic templates
3. Create adws/adw_modules/ structure
4. Add starter gateway scripts
5. Report created structure

### Agent: layer-auditor

Prompt structure:

- Scan codebase for agentic layer components
- Check for .claude/commands/, specs/, adws/
- Identify hooks, triggers, state management
- Report percentage coverage
- Recommend next investments

### Agent: layer-scaffolder

Prompt structure:

- Create minimum viable agentic layer
- Set up directory structure
- Create template slash commands
- Add basic gateway script
- Provide setup instructions

## Validation Criteria

- [x] Memory files follow kebab-case naming
- [x] Skills use `allowed-tools` (comma-separated string)
- [x] Agents use `tools` (array syntax)
- [x] Commands use kebab-case naming
- [x] No duplicates with existing plugin components
- [x] Content based on official course materials
- [ ] All files created and validated (post-implementation)

## Files to Create

| File | Type |
| ------ | ------ |
| `memory/agentic-layer-structure.md` | Memory |
| `memory/the-guiding-question.md` | Memory |
| `memory/gateway-script-patterns.md` | Memory |
| `memory/agentic-vs-application.md` | Memory |
| `skills/agentic-layer-audit/SKILL.md` | Skill |
| `skills/minimum-viable-agentic/SKILL.md` | Skill |
| `skills/task-based-multiagent/SKILL.md` | Skill |
| `skills/gateway-script-design/SKILL.md` | Skill |
| `commands/audit-layer.md` | Command |
| `commands/scaffold-layer.md` | Command |
| `agents/layer-auditor.md` | Agent |
| `agents/layer-scaffolder.md` | Agent |

## Files to Modify

| File | Action |
| ------ | -------- |
| `.claude-plugin/plugin.json` | Add new skills, commands, agents |
| `implementation-plan/MASTER-TRACKER.md` | Mark lesson 008 complete |

## Cross-References

- Culminates Lesson 1: Stop coding -> agents operate codebase
- Culminates Lesson 2: 12 leverage points -> build agentic layer
- Culminates Lesson 3: Templates -> encoded in agentic layer
- Culminates Lesson 4: PITER/ADWs -> core of agentic layer
- Culminates Lesson 5: Testing -> feedback loops in layer
- Culminates Lesson 6: Specialized agents -> primitives
- Culminates Lesson 7: ZTE -> target state of agentic layer

## Implementation Order

1. Create memory files (4 files)
2. Create skills (4 skills)
3. Create commands (2 commands)
4. Create agents (2 agents)
5. Update plugin.json
6. Update MASTER-TRACKER.md

---

**Plan Created:** 2025-12-04
**Status:** Ready for Implementation
