# Claude Code Ecosystem Reference

## CRITICAL REQUIREMENT: Official Documentation First

**MANDATORY RULE FOR ALL CLAUDE CODE TOPICS:**

1. **ALWAYS use the `docs-management` skill** to access official canonical documentation BEFORE answering questions, making changes, or providing guidance about ANY Claude Code topic
2. **NEVER make assumptions** or rely on memory - official documentation is the single source of truth
3. **ALL changes/modifications MUST be driven 100% by official canonical documentation** - this includes creating examples, providing configuration guidance, implementing features, writing documentation, and troubleshooting
4. **If official documentation is unclear or missing**, explicitly state this rather than guessing
5. **Verify against official docs** before claiming any feature exists or works a certain way

This applies to ALL Claude Code topics: hooks, memory, skills, subagents, MCP, plugins, settings, model config, workflows, SDK, and every other feature.

## Enforcement: Layered Defense

Specialized skills provide keyword registries and navigation, but **ALL authoritative content comes from docs-management**:

| Layer | Mechanism | Purpose |
| ----- | --------- | ------- |
| 1 | UserPromptSubmit Hook | Early warning at prompt time |
| 2 | MANDATORY Section in Skills | Direct enforcement when skill loads |
| 3 | CLAUDE.md Rule | Global backstop |

### Verification Checkpoint (MANDATORY)

Before responding to ANY Claude Code topic after a specialized skill loads:

- [ ] Did I invoke docs-management skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

**If ANY checkbox is unchecked, STOP and invoke docs-management first.**

### Failure Mode to Avoid

**WRONG:** Skill loads → Answer from keyword registry → Never invoke docs-management

**CORRECT:** Skill loads → Read keyword guidance → Invoke docs-management → Load official docs → Answer based on official docs

## Available Skills

Skills are provided by the **`claude-ecosystem` plugin** from the `claude-code-plugins` marketplace.

**Installation:** `/plugin install claude-ecosystem@claude-code-plugins`

| Topic | Skill | Purpose |
| ----- | ----- | ------- |
| Hooks | `hook-management` | Hook events, configuration, matchers, decision control |
| Memory | `memory-management` | CLAUDE.md, import syntax, hierarchy, commands |
| Skills | `skill-development` | Skill creation, YAML frontmatter, best practices |
| Subagents | `subagent-development` | Agent files, tool access, model selection |
| Slash Commands | `command-development` | Command creation, patterns, vs skills |
| Plugins | `plugin-development` | Plugin creation, distribution, hooks |
| MCP | `mcp-integration` | MCP servers, tools, connectors |
| Settings | `settings-management` | Settings files, hierarchy, environment vars |
| Output Styles | `output-customization` | Built-in styles, custom styles, switching |
| Status Line | `status-line-customization` | Custom status lines, JSON input, scripts |
| Security | `enterprise-security` | Security best practices, sandboxing, permissions |
| Permissions | `permission-management` | Permission rules, modes, tool access |
| Sandboxing | `sandbox-configuration` | Sandboxed bash, isolation, escape hatches |
| Agent SDK | `agent-sdk-development` | TypeScript/Python SDK, sessions, tools |
| Documentation | `docs-management` | Official Claude Code documentation access |
| Issue Lookup | `github-issues` (git plugin) | GitHub issues search, gh CLI, troubleshooting |
| Claude Code Issues | `claude-code-issue-researcher` agent | Known bugs, workarounds for anthropics/claude-code |

## Delegation Pattern

When a user asks about any Claude Code topic:

1. **Check for specialized skill**: Look up the topic in the Available Skills table above
2. **If specialized skill exists**: Invoke it first - it provides optimized keyword registries and decision trees
3. **Skill delegates to docs-management**: The specialized skill will guide efficient `docs-management` queries
4. **For topics without specialized skills**: Invoke `docs-management` directly with keywords from the topics index
5. **Base all guidance EXCLUSIVELY on official documentation** - no assumptions or memory

**Pattern Summary:**

- Topics WITH specialized skills: `User Question → Specialized Skill → docs-management → Official Docs`
- Topics WITHOUT specialized skills: `User Question → docs-management → Official Docs`

## Hybrid Documentation Strategy

### Two Documentation Sources

Claude Code documentation can be accessed via two complementary sources:

| Source | Invoke Via | Strengths |
| ------ | ---------- | --------- |
| `docs-management` skill | `Skill` tool | Fast (local cache), token-efficient (60-90% savings via subsections), curated, offline |
| `claude-code-guide` subagent | `Task` tool | Live web search, always current, fetches live URLs |

### Default Behavior: ALWAYS Parallel

For ALL Claude Code documentation queries, **invoke both sources in parallel** for maximum comprehensiveness:

1. **Invoke `docs-management` skill** - Fast local cache lookup
2. **Spawn `claude-code-guide` subagent in parallel** - Live web search
3. **Synthesize results** - Combine, deduplicate, note discrepancies

### Parallel Invocation Example

```markdown
# Main agent orchestrating both sources in parallel

[Skill tool: docs-management]
"Find documentation about Claude Code hooks"

[Task tool: claude-code-guide subagent] (parallel)
"Search official Claude Code documentation for hooks. Return key findings with source URLs."

[Synthesize]
Combine results, prioritize official sources, note if local cache differs from live docs.
```

### Why Both Sources

- **`docs-management`**: Provides fast, token-efficient access to curated local cache. Subsection extraction saves 60-90% tokens. Works offline.
- **`claude-code-guide`**: Provides live web search capabilities via WebFetch and WebSearch. Always has the most current documentation.

Using both in parallel ensures comprehensive coverage - local cache for speed and efficiency, live search for currency and gap-filling.

### Fallback (Plugin Not Installed)

If `claude-ecosystem` plugin is not installed (docs-management unavailable):

- Use `claude-code-guide` subagent only

### Key Constraint

**Agents cannot spawn subagents** - only the main conversation can use the Task tool. Therefore:

- The `docs-management` skill cannot invoke `claude-code-guide`
- The `docs-researcher` agent cannot spawn `claude-code-guide`
- Only the **main agent** can orchestrate running both in parallel

## Troubleshooting Strategy

### When Encountering Claude Code Errors

When troubleshooting Claude Code errors, unexpected behavior, or configuration problems, use a **three-source parallel strategy**:

| Source | Agent/Skill | Purpose |
| ------ | ----------- | ------- |
| Official Docs | `docs-management` skill | Correct usage, configuration, known limitations |
| GitHub Issues | `claude-code-issue-researcher` agent | Known bugs, workarounds, community solutions |
| Live Web | `claude-code-guide` subagent | Current discussions, recent fixes |

### Mandatory Troubleshooting Workflow

**When you see an error or unexpected behavior in Claude Code:**

1. **Search GitHub Issues FIRST** - Spawn `claude-code-issue-researcher` agent
   - Check if it's a known issue
   - Look for workarounds
   - Note if recently fixed (check closed issues)

2. **Consult Official Docs** - Invoke `docs-management` skill
   - Verify correct usage
   - Check for documented limitations
   - Find configuration requirements

3. **Synthesize and Report**
   - If known issue: Report issue number, status, and workaround
   - If not known: Suggest reporting if reproducible
   - Provide solution based on docs + community knowledge

### Example Troubleshooting Flow

```markdown
User: "I'm getting path doubling errors in my hooks on Windows"

1. [Task tool: claude-code-issue-researcher]
   "Search for path doubling Windows hooks errors"
   → Finds #11984, #5401, related issues
   → Notes workaround: use absolute paths

2. [Skill tool: docs-management]
   "Find documentation about hooks Windows paths"
   → Finds hook configuration guidance
   → Notes any platform-specific requirements

3. [Synthesize]
   "This is a known issue (#11984). Workaround: use absolute paths
   instead of cd && patterns. The issue is open and being tracked."
```

### Proactive Issue Checking Triggers

**Automatically search GitHub issues when:**

- User reports an error message
- Unexpected behavior occurs during Claude Code operations
- Platform-specific problems (Windows, macOS, Linux)
- Tool failures (Bash, Read, Edit, etc.)
- MCP server connection issues
- Hook execution failures
- Permission or sandbox errors

**Keywords that should trigger issue lookup:**

- "error", "bug", "broken", "not working", "fails", "crash"
- "known issue", "is this a bug", "anyone else", "workaround"
- Platform names: "Windows", "PowerShell", "macOS", "Linux", "WSL"

## Topics Index

For comprehensive topic listings with keywords, see `.claude/memory/claude-code-topics-index.md`. Load when you need to look up specific features, find keywords for docs-management queries, or navigate the Claude Code documentation.

---

**Last Updated:** 2025-12-05
