# Performance Quick Start Guide

## TL;DR - Immediate Wins

**To make Claude Code feel as fast or faster than Cursor:**

1. **Use parallelization** - 90% speedup for analysis tasks (see `.claude/memory/agent-usage-patterns.md`)
2. **Use Haiku model for simple tasks** - 2-3x faster, 4x cheaper
3. **Optimize tool usage** - Focused queries, not exhaustive searches
4. **Leverage subagent resumption** - Reuse context instead of re-invoking

## Why Claude Code Feels Slower Than Cursor

**Cursor's Approach:**

- Persistent codebase indexing (like LSP servers)
- Pre-processes entire codebase once
- Fast lookups from index
- Trade-off: Can become stale, requires re-indexing

**Claude Code's Approach:**

- On-demand discovery via Glob/Grep/Read tools
- No persistent index (always fresh)
- Discovery happens per-query
- Trade-off: Individual queries slower, but parallelization available

**Key Insight:** Different architectures, different optimization strategies. Cursor optimizes for indexed speed. Claude Code optimizes for freshness and parallelization.

## Parallelization and Agent Usage

For comprehensive guidance on parallelization strategies, model selection, agent communication, and best practices, see `.claude/memory/agent-usage-patterns.md`.

**Quick reference:**

- Run 3-5 independent subagents simultaneously for 90% speedup
- Use Haiku for simple tasks, Sonnet for complex reasoning, Opus for critical decisions
- Use subagent resumption to reuse context instead of re-initializing
- Parallelize when tasks are independent; run sequentially when dependencies exist

## Tool Optimization

**Principle:** Return high-signal information, not exhaustive dumps.

### Grep/Glob Best Practices

**Good (Focused):**

```bash
# Search specific patterns with context
Grep pattern="TODO|FIXME" path="src/" -C 2

# Find specific file types
Glob pattern="**/*.config.ts"
```

**Bad (Exhaustive):**

```bash
# Dump entire codebase
Grep pattern=".*" path="/"

# Search everything
Glob pattern="**/*"
```

### Context Window Awareness

**Default Claude Code limit:** 25,000 tokens per response

**Strategy:**

- Use `head_limit` parameter in Grep to cap results
- Use pagination for large result sets
- Filter at query time, not after retrieval
- Request summaries, not full content dumps

**Example:**

```text
Bad:  "Show me all functions in the codebase"
Good: "Show me authentication-related functions in src/auth/"
```

## Context Engineering

**Source:** `.claude/memory/context-engineering.md`

**Principle:** Treat context as finite resource with diminishing returns. Find smallest set of high-signal tokens that maximize outcomes.

### Progressive Disclosure Pattern

**Pre-load everything (bad):**

```text
1. Read all 50 files
2. Load entire codebase into context
3. Analyze
4. Context window exhausted, results mediocre
```

**Just-in-time loading (good):**

```text
1. Identify metadata/identifiers (file paths, function names)
2. Load specific content on-demand when needed
3. Keep context focused on high-signal information
4. Context window used efficiently, results excellent
```

### Hybrid Strategy (Optimal)

**Pre-load (Always in context):**

- CLAUDE.md and imports (~10k tokens)
- Current task context
- Recent conversation history

**Load on-demand (Just-in-time):**

- File contents (via Read tool)
- Search results (via Grep/Glob)
- External documentation (via WebFetch/MCP servers)
- Subagent results (via Task tool)

## Comparison: Claude Code vs Cursor

| Aspect | Cursor | Claude Code | Winner |
| ------ | ------ | ----------- | ------ |
| **Indexed lookups** | Fast (persistent index) | Slower (on-demand) | Cursor |
| **Freshness** | Can be stale | Always fresh | Claude Code |
| **Parallelization** | Limited | 3-5 agents (90% speedup) | Claude Code |
| **Setup required** | Index building | None | Claude Code |
| **Flexibility** | Index-dependent | Any codebase structure | Claude Code |
| **Token efficiency** | N/A | Optimized for context limits | Claude Code |

**Verdict:** Different architectures, different strengths. Claude Code can match or exceed Cursor's speed through parallelization, but requires different usage patterns.

## Practical Examples

### Example 1: Comprehensive Codebase Analysis

**Goal:** Analyze security, performance, style, and documentation

**Optimal approach:**

```markdown
I need comprehensive codebase analysis.

Launch 4 parallel Explore agents (Haiku model):
1. Security scan (check for vulnerabilities, secrets, unsafe patterns)
2. Performance analysis (identify bottlenecks, inefficiencies)
3. Style check (linting, formatting, consistency)
4. Documentation audit (completeness, accuracy, staleness)

Aggregate results when all complete.
```

**Time:** ~2 minutes (vs 8 minutes sequential)
**Speedup:** 75% reduction

### Example 2: Research Official Documentation

**Goal:** Validate setup guide against official documentation

**Optimal approach:**

```markdown
Use WebFetch or MCP server (ref, firecrawl) to fetch official docs
Model: Haiku (simple validation task)
Compare against existing docs
Report differences
```

**Time:** ~30 seconds (vs 2 minutes manual search)

### Example 3: Multi-Platform Documentation Update

**Goal:** Update installation guide across Windows/macOS/Linux variants

**Optimal approach:**

```markdown
Launch 3 parallel agents (Sonnet model for reasoning):
1. Update Windows variant
2. Update macOS variant
3. Update Linux variant

Each agent:
- Fetches latest official docs via MCP
- Updates version numbers
- Validates commands
- Ensures consistency

Aggregate when complete, review for cross-platform consistency.
```

**Time:** ~3 minutes (vs 10 minutes sequential)

## Future Optimization Opportunities

### Medium-Term (Weeks)

1. **MCP Server for Codebase Indexing**
   - Lightweight index that doesn't conflict with Cursor
   - Fast lookups like Cursor, freshness like Claude Code
   - Best of both worlds

2. **Tool Response Caching**
   - Memoize common Grep/Glob queries
   - Avoid re-running identical searches
   - Clear cache on file changes

3. **Performance Profiling Hooks**
   - Track tool execution time
   - Identify slow operations
   - Optimize hot paths

### Long-Term (Months)

1. **Persistent Incremental Indexing**
   - Similar to Cursor's approach
   - Incremental updates (not full re-index)
   - Opt-in feature

2. **Predictive Prefetching**
   - Anticipate likely next operations
   - Pre-load context before needed
   - ML-driven optimization

3. **Advanced Context Compaction**
   - Automated summarization of old context
   - Preserve critical information, discard noise
   - Extend effective context window

## Measurement and Verification

**How to measure improvement:**

1. **Time to completion:** Track how long tasks take with/without optimization
2. **Token usage:** Monitor context window efficiency
3. **Subjective feel:** Does Claude Code feel responsive?
4. **Parallel vs sequential:** Compare same task with different approaches

**Target metrics:**

- 90% speedup for parallelizable analysis tasks
- 2-3x speedup for simple tasks using Haiku
- 50-70% reduction in token usage through focused queries
- Cursor-level perceived performance through strategic optimization

## Related Documentation

- `.claude/memory/agent-usage-patterns.md` - Comprehensive agent and parallelization guidance
- `.claude/memory/context-engineering.md` - Advanced context optimization strategies
- `.claude/memory/tool-optimization.md` - Tool design principles for efficiency
- `.claude/memory/operational-rules.md` - Core operational guidelines

**Last Updated:** 2025-11-30
