# Lesson 007 Plan: ZTE - The Secret of Agentic Engineering

## Summary

Implement Lesson 007 "ZTE: The Secret of Agentic Engineering" for the tactical-agentic-coding plugin. This lesson teaches Zero-Touch Engineering - the third level of agentic coding where codebases ship themselves.

## Core Tactic

**Target Zero-Touch Engineering** - Progress from In-Loop (constant presence) to Out-Loop (prompt + review) to ZTE (prompt only). Build systems so reliable that human review becomes a bottleneck, not a safety net.

## Source Material Validated

- [x] Lesson content at `plugins/tactical-agentic-coding/lessons/lesson-007-zte-secret/`
- [x] Analysis at `plugins/tactical-agentic-coding/analysis/lesson-007-analysis.md`
- [x] Companion repo at `D:\repos\gh\disler\tac-7`
- [x] Official Claude Code docs validated

## Key Concepts from Lesson

### Three Levels of Agentic Coding

| Level | Description | Presence KPI |
| ------- | ------------- | -------------- |
| **In-Loop** | Interactive prompting, constant back-and-forth | High (constant) |
| **Out-Loop** | AFK agents, PITER framework, trigger-based | Medium (prompt + review) |
| **Zero-Touch** | Codebase ships itself, automated end-to-end | Low (prompt only) |

### ZTE Workflow: Plan -> Build -> Test -> Review -> Document -> Ship

The complete Zero-Touch Engineering workflow with automatic shipping.

### The Secret: Composable Agentic Primitives

> "The secret of tactical agentic coding is that it's not about the software developer lifecycle at all. It's about composable agentic primitives you can use to solve any engineering problem class."

### Git Worktrees for Agent Parallelization

- Isolated environments for concurrent agent execution
- Deterministic port allocation (9100-9114 backend, 9200-9214 frontend)
- Up to 15 concurrent instances

## Components to Create

### Memory Files (4 files)

Location: `plugins/tactical-agentic-coding/memory/`

| File | Purpose | Priority |
| ------ | --------- | ---------- |
| `zte-progression.md` | Three levels of agentic coding, presence KPIs, progression path | P1 |
| `composable-primitives.md` | The "secret" of TAC - primitives over SDLC | P1 |
| `git-worktree-patterns.md` | Worktree setup, isolation, port allocation | P2 |
| `zte-confidence-building.md` | How to build confidence for ZTE (chores -> bugs -> features) | P2 |

### Skills (4 skills)

Location: `plugins/tactical-agentic-coding/skills/`

| Skill | Purpose | Tools |
| ------- | --------- | ------- |
| `zte-progression` | Guide progression from In-Loop to ZTE | Read, Grep, Glob |
| `git-worktree-setup` | Set up Git worktrees for agent parallelization | Read, Grep, Glob |
| `agentic-kpi-tracking` | Track and measure agentic coding KPIs | Read, Grep, Glob |
| `composable-primitives` | Design composable agentic primitives | Read, Grep, Glob |

### Commands (3 commands)

Location: `plugins/tactical-agentic-coding/commands/`

| Command | Purpose | Arguments |
| --------- | --------- | ----------- |
| `install-worktree` | Set up isolated worktree environment | `$1` worktree_path, `$2` backend_port, `$3` frontend_port |
| `track-kpis` | Calculate and update agentic KPIs | `$ARGUMENTS` - state context |
| `ship` | Validate state and merge to main | `$1` branch_name |

### Agents (3 agents)

Location: `plugins/tactical-agentic-coding/agents/`

| Agent | Purpose | Tools | Model |
| ------- | --------- | ------- | ------- |
| `shipper` | Validate state completeness and execute merge to main | Read, Bash | sonnet |
| `worktree-installer` | Set up isolated worktree environments | Read, Write, Bash | haiku |
| `kpi-tracker` | Calculate and update agentic KPIs | Read, Write, Bash | haiku |

## Implementation Details

### Memory: zte-progression.md

Content outline:

- Three Levels definition with presence KPIs
- Progression path: In-Loop -> Out-Loop -> ZTE
- When to use each level
- Signs you're ready for next level
- Cross-reference to @agentic-kpis.md

### Memory: composable-primitives.md

Content outline:

- The "secret" quote and explanation
- Primitives vs SDLC thinking
- Examples of primitive compositions
- Organization-specific customization
- Building blocks approach

### Memory: git-worktree-patterns.md

Content outline:

- Why worktrees for agent parallelization
- Directory structure pattern
- Port allocation strategy (deterministic, 15 concurrent)
- Worktree creation and cleanup
- Alternatives (Docker, containerization)

### Memory: zte-confidence-building.md

Content outline:

- Progression path: chores -> bugs -> features
- Confidence milestones (5 runs, 20 runs, 5 consecutive)
- When human review becomes bottleneck
- Decision point criteria (90% confidence)
- Belief change required

### Skill: zte-progression

Workflow:

1. Assess current level (In-Loop, Out-Loop, ZTE)
2. Identify blockers to next level
3. Recommend specific improvements
4. Track progression metrics

### Skill: git-worktree-setup

Workflow:

1. Create worktree from origin/main
2. Allocate deterministic ports
3. Configure environment files
4. Set up MCP configuration
5. Install dependencies

### Skill: agentic-kpi-tracking

Workflow:

1. Parse existing KPI file
2. Calculate metrics (streak, attempts, size, presence)
3. Update summary and detail tables
4. Generate trend analysis

### Skill: composable-primitives

Workflow:

1. Identify problem class
2. Map to existing primitives
3. Design composition
4. Validate completeness

### Command: install-worktree

Steps:

1. Create `.ports.env` with port configuration
2. Copy and update environment files
3. Configure MCP for worktree paths
4. Install backend dependencies
5. Install frontend dependencies
6. Initialize database

### Command: track-kpis

Steps:

1. Read current KPI file
2. Parse state from arguments
3. Calculate new metrics
4. Update both tables
5. Report summary

### Command: ship

Steps:

1. Validate state completeness (all fields populated)
2. Validate worktree exists
3. Fetch and pull latest main
4. Merge branch with --no-ff
5. Push to origin
6. Post completion message

### Agent: shipper

Prompt structure:

- Validate ALL state fields populated
- Validate worktree exists (three-way check)
- Execute manual merge sequence
- Handle failures gracefully
- Return structured result

### Agent: worktree-installer

Prompt structure:

- Create worktree at specified path
- Configure ports in .ports.env
- Update environment files
- Setup MCP configuration
- Install dependencies
- Return installation status

### Agent: kpi-tracker

Prompt structure:

- Parse state for current workflow
- Calculate attempts (count plan/patch runs)
- Calculate diff statistics
- Update streak counts
- Return formatted KPI update

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
| `memory/zte-progression.md` | Memory |
| `memory/composable-primitives.md` | Memory |
| `memory/git-worktree-patterns.md` | Memory |
| `memory/zte-confidence-building.md` | Memory |
| `skills/zte-progression/SKILL.md` | Skill |
| `skills/git-worktree-setup/SKILL.md` | Skill |
| `skills/agentic-kpi-tracking/SKILL.md` | Skill |
| `skills/composable-primitives/SKILL.md` | Skill |
| `commands/install-worktree.md` | Command |
| `commands/track-kpis.md` | Command |
| `commands/ship.md` | Command |
| `agents/shipper.md` | Agent |
| `agents/worktree-installer.md` | Agent |
| `agents/kpi-tracker.md` | Agent |

## Files to Modify

| File | Action |
| ------ | -------- |
| `.claude-plugin/plugin.json` | Add new skills, commands, agents |
| `implementation-plan/MASTER-TRACKER.md` | Mark lesson 007 complete |

## Cross-References

- Builds on Lesson 002: KPIs lead to ZTE (Presence -> 1)
- Builds on Lesson 004: PITER framework -> PITE (drop Review)
- Builds on Lesson 005: Tests enable confidence for ZTE
- Builds on Lesson 006: Specialized agents execute each step

## Implementation Order

1. Create memory files (4 files)
2. Create skills (4 skills)
3. Create commands (3 commands)
4. Create agents (3 agents)
5. Update plugin.json
6. Update MASTER-TRACKER.md

---

**Plan Created:** 2025-12-04
**Status:** Ready for Implementation
