# Lesson 2 Analysis: The 12 Leverage Points of Agentic Coding

## Content Summary

### Core Tactic

**Adopt Your Agent's Perspective** - Your agent is brilliant but blind. With every new session, it starts as a blank instance - ephemeral, no context, no memories. If you want your agent to perform like you would, it needs your perspective: the information, tools, and resources you would use to solve the problem.

### Key Frameworks

#### The 12 Leverage Points of Agentic Coding

**In-Agent Leverage Points (The Core Four):**

| # | Leverage Point | Description |
| - | -------------- | ----------- |
| 1 | **Context** | What can your agent see in its context window? |
| 2 | **Model** | The engine of your agent (reasoning capabilities) |
| 3 | **Prompt** | Your instructions to the agent |
| 4 | **Tools** | Capabilities for action (bash, read, write, web, delegation) |

**Through-Agent Leverage Points:**

| # | Leverage Point | Description |
| - | -------------- | ----------- |
| 5 | **Standard Out** | Clear logging throughout applications guides agents to success |
| 6 | **Types** | IDKs (Information Dense Keywords) that trace data flow |
| 7 | **Documentation** | Agent-specific context (internal/external) |
| 8 | **Tests** | Validation and self-correction (highest leverage!) |
| 9 | **Architecture** | Consistent, navigable codebase structure |
| 10 | **Plans** | Meta-work communication (prompts that are plans) |
| 11 | **Templates** | Reusable prompts (slash commands) |
| 12 | **ADWs** | AI Developer Workflows (prompts + code + triggers) |

#### Agentic Coding KPIs

| KPI | Direction | Description |
| --- | --------- | ----------- |
| **Size** | UP | Increase the size/scope of work handed to agents |
| **Attempts** | DOWN | Reduce iterations needed per task |
| **Streak** | UP | Back-to-back one-shot successes |
| **Presence** | DOWN | Minimize human intervention (target: zero) |

#### Phase 2 Software Development Lifecycle

```text
Plan -> Code -> Test -> Review -> Document
```

### Implementation Patterns from Repo (tac-2)

1. **Prime Command** - Context priming pattern:

   ```markdown
   # Prime
   > Execute the following sections to understand the codebase then summarize.
   ## Run
   git ls-files
   ## Read
   README.md
   ```

2. **Install Command** - Composable command pattern:

   ```markdown
   # Install & Prime
   ## Read and Execute
   .claude/commands/prime.md
   ## Run
   Install FE and BE dependencies
   ```

3. **Tools Command** - Agent introspection:

   ```markdown
   # List Built-in Tools
   List all core, built-in non-mcp development tools available to you.
   Display in bullet format. Use typescript function syntax with parameters.
   ```

4. **Standard Out Pattern** - Making errors visible to agents:
   - Print success/error to stdout for every API endpoint
   - Agent can run server and see live output
   - Errors visible in context window for self-correction

5. **Type Tracing** - Following data flow:
   - Types as IDKs (Information Dense Keywords)
   - Search for type name to find all usages
   - Trace flow: Model -> Server -> Client -> Render

6. **Architecture Patterns** - Agent-navigable structure:
   - Clear entry points (server.py, main.ts)
   - Client/server separation cuts search space in half
   - Tests mirror source structure
   - Files < 1000 lines
   - Verbose, meaningful names

7. **Permission Configuration** - Scoped access with deny list:

   ```json
   {
     "permissions": {
       "allow": ["Bash(mkdir:*)", "Bash(uv:*)", ...],
       "deny": ["Bash(git push --force:*)", "Bash(rm -rf:*)"]
     }
   }
   ```

### Anti-Patterns Identified

- **Missing Standard Out**: Errors bubble up without trace - agent can't see
- **Vague Type Names**: `DataRequest` instead of `FileUploadRequest`
- **Inconsistent Architecture**: Different patterns in different parts of codebase
- **No Tests**: Agent can't self-validate
- **High Presence**: Constant prompting back and forth

### Metrics/KPIs

- **One-shot success rate**: First-try completions without iteration
- **Streak length**: Consecutive one-shot successes
- **Agent run duration**: Minutes to hours of autonomous work
- **Presence level**: 0 = fully autonomous, higher = more babysitting

## Extracted Components

### Skills

| Name | Purpose | Keywords |
| ---- | ------- | -------- |
| `leverage-point-audit` | Audit codebase for 12 leverage point coverage | leverage, audit, agentic, improve |
| `standard-out-setup` | Add stdout logging to API endpoints | logging, stdout, errors, visibility |

### Subagents

| Name | Purpose | Tools |
| ---- | ------- | ----- |
| None for Lesson 2 | Concepts, not specific agent patterns | N/A |

### Commands

| Name | Purpose | Arguments |
| ---- | ------- | --------- |
| `/prime` | Prime agent with codebase context | None |
| `/tools` | List available tools | None |

### Memory Files

| Name | Purpose | Load Condition |
| ---- | ------- | -------------- |
| `12-leverage-points.md` | Complete leverage point reference | When improving agentic coding |
| `agentic-kpis.md` | KPI definitions and measurement guidance | When measuring success |
| `agent-perspective-checklist.md` | Questions to ask from agent's view | Before starting agentic tasks |

## Key Insights for Plugin Development

### High-Value Components from Lesson 2

1. **Memory File: `12-leverage-points.md`**
   - Complete reference of all 12 leverage points
   - In-Agent vs Through-Agent categorization
   - Examples and anti-patterns for each

2. **Memory File: `agentic-kpis.md`**
   - Size, Attempts, Streak, Presence definitions
   - How to measure each KPI
   - Target values for improvement

3. **Skill: `leverage-point-audit`**
   - Analyze codebase for leverage point coverage
   - Report gaps and recommendations
   - Prioritized action items

4. **Command Templates: `/prime`, `/tools`**
   - These are foundational patterns every codebase should have
   - Context priming before work
   - Tool introspection for capability awareness

### Codebase Architecture Recommendations

The lesson provides actionable architecture guidance that should be encoded:

- Clear entry points per service
- Constant files for unchanging information
- Types/classes/structures for data modeling
- Verbose, information-dense naming
- Files < 1000 lines
- README/CLAUDE.md throughout codebase
- Separated services (client/server)
- One responsibility per file
- Test files mirror source structure

## Validation Checklist

- [x] Read video.md (metadata)
- [x] Read lesson.md (structured summary)
- [x] Read captions.txt (full transcript - 47:15 of content!)
- [x] Explored tac-2 repository
- [x] Read .claude/commands/prime.md
- [x] Read .claude/commands/install.md
- [x] Read .claude/commands/tools.md
- [x] Read .claude/settings.json
- [x] Read README.md
- [x] Read specs/init_nlq_to_sql_to_table.md (detailed plan example)
- [x] Read app/server/core/data_models.py (type examples)
- [x] Validated against official docs (2025-12-04) - See DOCUMENTATION_AUDIT.md

## Cross-Lesson Dependencies

- **Builds on Lesson 1**: Core Four now has 8 additional leverage points
- **Sets up Lesson 3**: Plans as leverage point - next lesson dives deep
- **Sets up Lesson 4**: ADWs mentioned - expanded in AFK agents lesson
- **Sets up Lesson 5**: Tests as highest leverage - dedicated lesson
- **Sets up Lesson 6**: Agent specialization (one purpose)
- **Sets up Lesson 7**: Zero presence KPI target - ZTE lesson

## Notable Quotes

> "Your agent is brilliant, but blind."
> "If you're not writing tests, you're probably vibe coding."
> "Types are IDKs - Information Dense Keywords."
> "The goal is one-shot agentic coding success."
> "We're not here to become a babysitter for AI agents."

---

**Analysis Date:** 2025-12-04
**Analyzed By:** Claude Code (claude-opus-4-5-20251101)
