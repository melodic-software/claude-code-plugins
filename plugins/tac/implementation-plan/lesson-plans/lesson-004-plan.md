# Lesson 004: AFK Agents - Implementation Plan

**Created:** 2025-12-04
**Status:** Ready for Implementation
**Companion Repo:** `D:\repos\gh\disler\tac-4`

---

## Lesson Summary

- **Core Tactic**: Stay Out The Loop - build AFK (Away From Keyboard) agents that run autonomously using the PITER framework
- **Key Frameworks**: PITER (Prompt Input, Trigger, Environment, Review), AI Developer Workflows (ADWs), In-Loop vs Out-of-Loop agentic coding

---

## Source Materials Reviewed

- [x] `lessons/lesson-004-afk-agents/lesson.md`
- [x] `lessons/lesson-004-afk-agents/captions.txt` (transcript - 46:27 of content)
- [x] `analysis/lesson-004-analysis.md`
- [x] `analysis/CONSOLIDATION.md` (relevant sections)
- [x] `analysis/DOCUMENTATION_AUDIT.md` (relevant sections)
- [x] Companion repo explored (tac-4)
- [x] Official hooks documentation validated

---

## Components to Implement

### Skills

| Name | Purpose | allowed-tools | Priority |
| ------ | --------- | --------------- | ---------- |
| `adw-design` | Guide creation of AI Developer Workflows combining deterministic code with non-deterministic agents | Read, Grep, Glob | P1 |
| `piter-setup` | Set up PITER framework elements for AFK agent systems | Read, Grep, Glob | P1 |
| `issue-classification` | Configure issue classification for ADWs (chore/bug/feature routing) | Read, Grep, Glob | P2 |

### Agents

| Name | Purpose | tools | model | Priority |
| ------ | --------- | ------- | ------- | ---------- |
| `sdlc-planner` | Generate implementation plans from GitHub issues | [Read, Write, Glob, Grep] | sonnet | P1 |
| `sdlc-implementer` | Implement plans with validation | [Read, Write, Edit, Bash] | sonnet | P1 |
| `issue-classifier` | Classify GitHub issues into problem classes | [Read] | haiku | P2 |

**Note:** Branch generator, PR creator, and committer agents are too tightly coupled to the ADW Python scripts in tac-4. These are best implemented as part of a full ADW system rather than standalone Claude Code subagents.

### Commands

| Name | Purpose | Arguments | Priority |
| ------ | --------- | ----------- | ---------- |
| `/classify-issue` | Classify GitHub issue type (chore/bug/feature) | `$ARGUMENTS` - issue JSON or description | P1 |
| `/generate-branch-name` | Generate semantic branch name from issue context | `$1` type, `$2` issue description | P2 |
| `/commit-with-agent` | Create formatted commit with agent attribution | `$1` agent name, `$ARGUMENTS` - commit context | P2 |
| `/pull-request` | Create PR with full context linking back to issue | `$ARGUMENTS` - branch, issue, plan context | P2 |

**Note:** These are simplified versions of the tac-4 commands. The full ADW orchestration requires Python/TypeScript scripts, not just slash commands.

### Memory Files

| Name | Purpose | Load Condition | Priority |
| ------ | --------- | ---------------- | ---------- |
| `piter-framework.md` | Complete PITER framework reference | When setting up AFK agents | P1 |
| `adw-anatomy.md` | ADW structure and design patterns | When building AI Developer Workflows | P1 |
| `outloop-checklist.md` | Checklist for out-of-loop systems | Before deploying AFK agents | P1 |
| `inloop-vs-outloop.md` | Comparison of in-loop and out-of-loop patterns | When deciding agent architecture | P2 |

### Other Components

None - hooks would require Python scripts which are out of scope for the plugin (hooks are project-specific, not portable across projects).

---

## Implementation Order

1. **Memory Files First** (foundational understanding)
   - `piter-framework.md` - PITER elements reference
   - `adw-anatomy.md` - ADW structure patterns
   - `outloop-checklist.md` - deployment readiness
   - `inloop-vs-outloop.md` - architecture decision guide

2. **Skills Second** (workflow guidance)
   - `adw-design` skill
   - `piter-setup` skill
   - `issue-classification` skill

3. **Commands Third** (building blocks)
   - `/classify-issue` command
   - `/generate-branch-name` command
   - `/commit-with-agent` command
   - `/pull-request` command

4. **Agents Last** (specialized workers)
   - `sdlc-planner` agent
   - `sdlc-implementer` agent
   - `issue-classifier` agent

---

## Memory File Content Specifications

### 1. piter-framework.md

**Purpose**: Complete PITER framework reference for AFK agents

**Content Outline**:

- What is PITER: The four elements of AFK agents
- **P - Prompt Input**: Sources of work requests
  - GitHub Issues (title + body = prompt)
  - Notion databases
  - Slack messages
  - Email triggers
- **I - (Implicit)**: Issue classification
  - Classify as chore/bug/feature
  - Route to appropriate template
- **T - Trigger**: What kicks off the workflow
  - GitHub Webhooks (real-time)
  - Cron jobs (polling)
  - Manual CLI invocation
- **E - Environment**: Where agents run
  - Dedicated device/sandbox
  - Isolated from development machine
  - Full permissions (`--dangerously-skip-permissions`)
- **R - Review**: Human oversight point
  - Pull Requests for code review
  - Optional: Skip for Zero Touch Engineering (ZTE)
- Implementation options for each element
- Connection to Lesson 7 (ZTE)

### 2. adw-anatomy.md

**Purpose**: ADW structure and design patterns

**Content Outline**:

- What is an ADW (AI Developer Workflow)
  - Synthesis of deterministic code + non-deterministic agents
  - Reusable agentic workflows
  - Highest composition level of agentic coding
- ADW Structure Pattern:

  ```text
  adws/
    main_workflow.py       # Main orchestrator
    agent.py               # Claude Code integration
    data_types.py          # Type definitions
    github.py              # External service integration
    trigger_*.py           # Trigger implementations
    health_check.py        # Environment validation
  ```

- Key Components:
  - Orchestrator (Python/TypeScript)
  - Micro agents (specialized workers)
  - Triggers (webhook, cron, manual)
  - Observability (logging, issue comments)
- ADW ID tracking pattern (8-char UUID)
- Model selection strategy by agent role
- Anti-patterns to avoid

### 3. outloop-checklist.md

**Purpose**: Checklist before deploying AFK agents

**Content Outline**:

- Environment Checklist:
  - [ ] Dedicated machine/sandbox available
  - [ ] API keys configured securely
  - [ ] Repository access configured
  - [ ] Permissions configured (`--dangerously-skip-permissions`)
- Trigger Checklist:
  - [ ] Webhook endpoint reachable (ngrok/cloudflare tunnel)
  - [ ] GitHub webhook configured
  - [ ] Health check endpoint available
- Workflow Checklist:
  - [ ] All templates tested (chore, bug, feature)
  - [ ] Issue classification accurate
  - [ ] Branch naming works
  - [ ] PR creation succeeds
- Observability Checklist:
  - [ ] Logging configured
  - [ ] Issue comments working
  - [ ] Error handling in place
- Review Process:
  - [ ] PR review workflow defined
  - [ ] Rollback procedure documented
  - [ ] Emergency stop mechanism

### 4. inloop-vs-outloop.md

**Purpose**: Guide for choosing between in-loop and out-of-loop patterns

**Content Outline**:

- In-Loop Agentic Coding:
  - You at your device, prompting back and forth
  - Human is active participant
  - Good for: exploration, learning, complex decisions
  - KPIs: Streak (consistency), Attempts (efficiency)
- Out-of-Loop Agentic Coding:
  - Agents run autonomously
  - Human defines work, reviews results
  - Good for: repetitive tasks, well-defined problems
  - KPIs: Presence (target 1), Size (larger work units)
- Decision Matrix:

  | Factor | In-Loop | Out-of-Loop |
  | -------- | --------- | ------------- |
  | Problem clarity | Ambiguous | Well-defined |
  | Template exists | No | Yes |
  | Risk tolerance | High | Low-medium |
  | Iteration speed | Fast | Batch |

- Progression Path: In-Loop -> Out-of-Loop -> ZTE

---

## SDK-Only Components (Not Implemented)

The following patterns from tac-4 require full Python/TypeScript implementation and are not portable as Claude Code plugin components:

| Component | Why SDK-Only | Implementation Path |
| ----------- | -------------- | --------------------- |
| Full ADW orchestration | Requires Python subprocess management | Reference implementation in tac-4 |
| Webhook trigger server | HTTP server + webhook handling | Python FastAPI/Flask |
| Cron trigger polling | Continuous polling loop | Python script + systemd |
| Hook implementations | Project-specific Python scripts | Project `.claude/hooks/` directory |
| Agent output logging | JSONL file management | Python in ADW scripts |

These are documented in memory files as reference patterns, not as plugin components.

---

## Validation Criteria

- [x] All components pass docs-management validation
- [x] Hooks patterns validated against official docs
- [x] No duplicate functionality with existing plugins
- [x] Naming conventions followed (noun-phrase skills, verb-phrase commands, kebab-case)
- [x] Skill `allowed-tools` is comma-separated (not array)
- [x] Agent `tools` is array
- [ ] Model IDs are Dec 2025 versions (use in agent frontmatter)

---

## Python-to-TypeScript Transformations Required

This lesson primarily uses Python for ADW orchestration. The plugin components are slash commands and memory files, not SDK code. The ADW patterns are documented as reference implementations.

| Python Pattern (from repo) | Plugin Equivalent |
| ---------------------------- | ------------------- |
| `adw_plan_build.py` | Reference documentation in `adw-anatomy.md` |
| `agent.py` subprocess calls | CLI invocation patterns in memory |
| `data_types.py` Pydantic models | Not needed (memory files only) |
| Hook Python scripts | Not implemented (project-specific) |

---

## Key Patterns from Companion Repo

### CLAUDE.md Patterns

No CLAUDE.md in tac-4 - ADW orchestrator handles context.

### ADW Workflow Pattern

```text
GitHub Issue
    ↓
Classify Issue → Determine type (bug/feature/chore)
    ↓
Create Branch → Semantic branch name
    ↓
Plan Phase → Execute /bug, /feature, or /chore
    ↓
Build Phase → Execute /implement
    ↓
PR Creation → Push branch, create PR
```yaml

### Model Selection Strategy

| Agent | Model | Rationale |
| ------- | ------- | ----------- |
| Classifier | Haiku | Fast, simple decision |
| Planner | Sonnet/Opus | Complex reasoning |
| Implementer | Sonnet/Opus | Complex implementation |
| Branch Generator | Haiku | Simple string generation |
| PR Creator | Haiku | Formatting, not reasoning |

### Hook Patterns (Reference Only)

From tac-4 `.claude/hooks/`:

- `pre_tool_use.py` - Block dangerous commands, log tool invocations
- `post_tool_use.py` - Capture execution state after tools run
- `notification.py` - Optional TTS notifications
- `stop.py` - Capture session end state

---

## Dependencies

### Builds On

- **Lesson 001**: Programmable Claude Code from shell/Python
- **Lesson 002**: 12 leverage points - ADWs are leverage point #12
- **Lesson 003**: Templates chained into ADWs

### Required By

- **Lesson 005**: Closing the loops with validation
- **Lesson 006**: Specialized micro agents
- **Lesson 007**: ZTE (Zero Touch Engineering) goal

---

## Notes

1. **Hooks are project-specific** - The Python hook scripts in tac-4 are project-specific and not portable. Document the patterns but don't implement as plugin components.

2. **ADW orchestration is SDK territory** - The full ADW pattern (Python orchestrator + Claude Code CLI calls) is outside the scope of a Claude Code plugin. Document as reference implementation.

3. **Simplified commands** - The commands we implement are building blocks that could be used in an ADW, but the full orchestration requires external code.

4. **Focus on concepts** - The primary value of this lesson for the plugin is the conceptual frameworks (PITER, ADW anatomy, in-loop vs out-of-loop) encoded in memory files.

5. **Connection to ZTE** - This lesson sets up Lesson 7's Zero Touch Engineering goal by introducing the "Presence: DOWN" KPI target.

---

## Completion Checklist

- [x] All source materials reviewed
- [x] Companion repo explored
- [x] docs-management skill invoked for validation
- [x] All components listed with priorities
- [x] Implementation order defined
- [x] Memory file content specified
- [x] SDK-only components documented
- [ ] Implementation completed
- [ ] MASTER-TRACKER updated

---

**Plan Status**: Ready for Implementation
